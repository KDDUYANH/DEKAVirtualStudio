//
//  LUTLibrary.swift
//  Import / preview / enable / intensity / delete / favorites. LUT files live in
//  Application Support/LUTs (on device only). GPU textures are cached by id.
//

import Foundation
import Metal

struct LUTItem: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var size: Int
    var favorite: Bool
    var fileName: String
    var isBuiltIn: Bool = false
}

final class LUTLibrary {

    private let device: MTLDevice
    private let directory: URL
    private let indexURL: URL
    private(set) var items: [LUTItem] = []
    private let cache = Locked<[String: LoadedLUT]>([:])

    init(device: MTLDevice) {
        self.device = device
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("LUTs", isDirectory: true)
        indexURL = directory.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        loadIndex()
        installBuiltIns()
    }

    // MARK: Index

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([LUTItem].self, from: data) else { return }
        items = list.filter { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0.fileName).path) }
    }

    private func saveIndex() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            Log.project.error("LUT index save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Ships sample LUTs from the bundle (Resources/*.cube) the first time.
    private func installBuiltIns() {
        let bundled = Bundle.main.urls(forResourcesWithExtension: "cube", subdirectory: nil) ?? []
        for url in bundled where !items.contains(where: { $0.fileName == url.lastPathComponent }) {
            if let item = try? importFile(at: url, securityScoped: false, builtIn: true) {
                Log.project.info("Installed built-in LUT \(item.name, privacy: .public)")
            }
        }
    }

    // MARK: Operations

    /// Validates (parses) before accepting: a broken LUT never reaches the GPU.
    @discardableResult
    func importFile(at url: URL, securityScoped: Bool = true, builtIn: Bool = false) throws -> LUTItem {
        let scoped = securityScoped && url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let name = url.deletingPathExtension().lastPathComponent
        let lut = try CubeLUTParser.parse(data: data, fallbackTitle: name)
        let id = UUID().uuidString
        let fileName = builtIn ? url.lastPathComponent : "\(id).cube"
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
        let item = LUTItem(id: id, name: lut.title.isEmpty ? name : lut.title, size: lut.size,
                           favorite: false, fileName: fileName, isBuiltIn: builtIn)
        items.append(item)
        saveIndex()
        return item
    }

    func delete(id: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: idx)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(item.fileName))
        cache.mutate { $0[id] = nil }
        saveIndex()
    }

    func toggleFavorite(id: String) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        items[idx].favorite.toggle()
        saveIndex()
    }

    var sortedItems: [LUTItem] {
        items.sorted { ($0.favorite ? 0 : 1, $0.name) < ($1.favorite ? 0 : 1, $1.name) }
    }

    /// Parses + uploads once, then served from cache (thread-safe; called off the render thread).
    func load(id: String) throws -> LoadedLUT {
        if let hit = cache.get()[id] { return hit }
        guard let item = items.first(where: { $0.id == id }) else {
            throw CubeLUTError.missingSize
        }
        let data = try Data(contentsOf: directory.appendingPathComponent(item.fileName))
        let lut = try CubeLUTParser.parse(data: data, fallbackTitle: item.name)
        let tex = try LUTTextureFactory.makeTexture(device: device, lut: lut)
        let loaded = LoadedLUT(id: id, lut: lut, texture: tex)
        cache.mutate { $0[id] = loaded }
        return loaded
    }

    /// Raw file bytes, used for project export.
    func fileData(id: String) -> Data? {
        guard let item = items.first(where: { $0.id == id }) else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(item.fileName))
    }

    /// Imports raw bytes (project import) keeping the original id so scenes still resolve.
    func importData(_ data: Data, id: String, name: String) throws {
        if items.contains(where: { $0.id == id }) { return }
        let lut = try CubeLUTParser.parse(data: data, fallbackTitle: name)
        let fileName = "\(id).cube"
        try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
        items.append(LUTItem(id: id, name: name, size: lut.size, favorite: false, fileName: fileName))
        saveIndex()
    }
}
