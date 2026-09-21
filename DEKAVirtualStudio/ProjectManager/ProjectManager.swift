//
//  ProjectManager.swift
//  New / Save / Load / Duplicate / Export / Import.
//
//  On disk:  Documents/Projects/<uuid>/project.json  +  assets/ (backgrounds, logos)
//  Export:   one self-contained "<name>.deka.json" (project + embedded assets + LUTs, base64)
//
//  Loading merges the saved JSON over a default project, so files written by older versions
//  (missing newer keys) still open.
//

import Foundation

struct ProjectSummary: Identifiable, Equatable {
    let id: UUID
    let name: String
    let modifiedAt: Date
}

/// Portable export format.
struct ProjectArchive: Codable {
    var format = "dtek.studio.project"
    var version = 1
    var project: StudioProject
    var assets: [String: Data]              // file name → bytes
    var luts: [ArchivedLUT]
}

struct ArchivedLUT: Codable {
    let id: String
    let name: String
    let data: Data
}

enum ProjectError: LocalizedError {
    case notFound, invalidArchive
    var errorDescription: String? {
        switch self {
        case .notFound: return "Project not found."
        case .invalidArchive: return "This file is not a D-TEK Studio project."
        }
    }
}

final class ProjectManager {

    let root: URL
    private let fm = FileManager.default

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Projects", isDirectory: true)
        try? fm.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    // MARK: Paths

    func folder(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func assetsFolder(for id: UUID) -> URL { folder(for: id).appendingPathComponent("assets", isDirectory: true) }
    func assetURL(projectID: UUID, name: String) -> URL? {
        let url = assetsFolder(for: projectID).appendingPathComponent(name)
        return fm.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: Coding

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Decode with defaults: missing keys are filled from a default project / scene.
    static func decodeProject(from data: Data) throws -> StudioProject {
        guard var loaded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProjectError.invalidArchive
        }
        let defaults = try JSONSerialization.jsonObject(with: encoder.encode(StudioProject(name: "Untitled"))) as! [String: Any]
        let sceneDefaults = try JSONSerialization.jsonObject(with: encoder.encode(SceneModel(name: "Scene"))) as! [String: Any]
        if let scenes = loaded["scenes"] as? [[String: Any]] {
            loaded["scenes"] = scenes.map { deepMerge(sceneDefaults, $0) }
        }
        let merged = deepMerge(defaults, loaded)
        let mergedData = try JSONSerialization.data(withJSONObject: merged)
        return try decoder.decode(StudioProject.self, from: mergedData)
    }

    static func deepMerge(_ base: [String: Any], _ over: [String: Any]) -> [String: Any] {
        var out = base
        for (k, v) in over {
            if let b = base[k] as? [String: Any], let o = v as? [String: Any] {
                out[k] = deepMerge(b, o)
            } else if !(v is NSNull) || base[k] == nil {
                out[k] = v
            }
        }
        return out
    }

    // MARK: CRUD

    func list() -> [ProjectSummary] {
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return dirs.compactMap { dir in
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("project.json")),
                  let p = try? Self.decodeProject(from: data) else { return nil }
            return ProjectSummary(id: p.id, name: p.name, modifiedAt: p.modifiedAt)
        }.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func create(name: String) throws -> StudioProject {
        let p = StudioProject(name: name)
        try save(p)
        return p
    }

    func save(_ project: StudioProject) throws {
        var p = project
        p.modifiedAt = Date()
        try fm.createDirectory(at: assetsFolder(for: p.id), withIntermediateDirectories: true)
        try Self.encoder.encode(p).write(to: folder(for: p.id).appendingPathComponent("project.json"), options: .atomic)
    }

    func load(id: UUID) throws -> StudioProject {
        let url = folder(for: id).appendingPathComponent("project.json")
        guard let data = try? Data(contentsOf: url) else { throw ProjectError.notFound }
        return try Self.decodeProject(from: data)
    }

    func duplicate(id: UUID) throws -> StudioProject {
        var p = try load(id: id)
        let oldID = p.id
        p.id = UUID()
        p.name += " Copy"
        p.createdAt = Date()
        try fm.createDirectory(at: folder(for: p.id), withIntermediateDirectories: true)
        if fm.fileExists(atPath: assetsFolder(for: oldID).path) {
            try fm.copyItem(at: assetsFolder(for: oldID), to: assetsFolder(for: p.id))
        }
        try save(p)
        return p
    }

    func delete(id: UUID) throws {
        try fm.removeItem(at: folder(for: id))
    }

    /// Copies an imported file (background/logo) into the project, returns its asset name.
    func addAsset(projectID: UUID, from url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try fm.createDirectory(at: assetsFolder(for: projectID), withIntermediateDirectories: true)
        let name = "\(UUID().uuidString.prefix(8))-\(url.lastPathComponent)"
        try fm.copyItem(at: url, to: assetsFolder(for: projectID).appendingPathComponent(name))
        return name
    }

    // MARK: Export / Import

    func export(_ project: StudioProject, luts: LUTLibrary) throws -> URL {
        var assets: [String: Data] = [:]
        let folder = assetsFolder(for: project.id)
        for file in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] {
            assets[file] = try Data(contentsOf: folder.appendingPathComponent(file))
        }
        let lutIDs = Set(project.scenes.compactMap { $0.lut.lutID })
        let archived: [ArchivedLUT] = lutIDs.compactMap { id in
            guard let data = luts.fileData(id: id), let item = luts.items.first(where: { $0.id == id }) else { return nil }
            return ArchivedLUT(id: id, name: item.name, data: data)
        }
        let archive = ProjectArchive(project: project, assets: assets, luts: archived)
        let safeName = project.name.replacingOccurrences(of: "/", with: "-")
        let url = fm.temporaryDirectory.appendingPathComponent("\(safeName).dtek.json")
        try Self.encoder.encode(archive).write(to: url, options: .atomic)
        return url
    }

    func importArchive(from url: URL, luts: LUTLibrary) throws -> StudioProject {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fmt = obj["format"] as? String,
              fmt == "dtek.studio.project" || fmt == "deka.virtualstudio.project",
              let projectObj = obj["project"] else { throw ProjectError.invalidArchive }
        var project = try Self.decodeProject(from: JSONSerialization.data(withJSONObject: projectObj))
        struct Payload: Decodable { let assets: [String: Data]; let luts: [ArchivedLUT] }
        let payload = try Self.decoder.decode(Payload.self, from: data)

        // A new identity, so importing twice never overwrites.
        project.id = UUID()
        try fm.createDirectory(at: assetsFolder(for: project.id), withIntermediateDirectories: true)
        for (name, bytes) in payload.assets where !name.contains("/") && !name.hasPrefix(".") {
            try bytes.write(to: assetsFolder(for: project.id).appendingPathComponent(name), options: .atomic)
        }
        for lut in payload.luts { try luts.importData(lut.data, id: lut.id, name: lut.name) }
        try save(project)
        return project
    }
}
