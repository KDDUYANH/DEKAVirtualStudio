//
//  CubeLUTParser.swift
//  Adobe/Resolve .cube (3D) parser. Pure Swift, unit tested.
//  Spec notes: red varies fastest, then green, then blue. Values may exceed 0…1 (HDR LUTs);
//  DOMAIN_MIN/MAX default to 0/1.
//

import Foundation
import simd

struct CubeLUT: Equatable {
    var title: String
    var size: Int
    var domainMin: SIMD3<Float>
    var domainMax: SIMD3<Float>
    /// size³ RGB triples, red fastest.
    var values: [SIMD3<Float>]

    static func identity(size: Int) -> CubeLUT {
        var v: [SIMD3<Float>] = []
        v.reserveCapacity(size * size * size)
        let d = Float(size - 1)
        for b in 0..<size { for g in 0..<size { for r in 0..<size {
            v.append(SIMD3(Float(r) / d, Float(g) / d, Float(b) / d))
        } } }
        return CubeLUT(title: "Identity \(size)", size: size, domainMin: .zero, domainMax: .one, values: v)
    }

    /// CPU reference trilinear lookup (used by tests and diagnostics to validate the GPU path).
    func sample(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let n = simd_clamp((c - domainMin) / (domainMax - domainMin), .zero, .one) * Float(size - 1)
        let i0 = SIMD3<Int>(Int(n.x.rounded(.down)), Int(n.y.rounded(.down)), Int(n.z.rounded(.down)))
        let i1 = SIMD3<Int>(min(i0.x + 1, size - 1), min(i0.y + 1, size - 1), min(i0.z + 1, size - 1))
        let f = n - SIMD3<Float>(Float(i0.x), Float(i0.y), Float(i0.z))
        func at(_ r: Int, _ g: Int, _ b: Int) -> SIMD3<Float> { values[r + g * size + b * size * size] }
        let c00 = simd_mix(at(i0.x, i0.y, i0.z), at(i1.x, i0.y, i0.z), SIMD3(repeating: f.x))
        let c10 = simd_mix(at(i0.x, i1.y, i0.z), at(i1.x, i1.y, i0.z), SIMD3(repeating: f.x))
        let c01 = simd_mix(at(i0.x, i0.y, i1.z), at(i1.x, i0.y, i1.z), SIMD3(repeating: f.x))
        let c11 = simd_mix(at(i0.x, i1.y, i1.z), at(i1.x, i1.y, i1.z), SIMD3(repeating: f.x))
        let c0 = simd_mix(c00, c10, SIMD3(repeating: f.y))
        let c1 = simd_mix(c01, c11, SIMD3(repeating: f.y))
        return simd_mix(c0, c1, SIMD3(repeating: f.z))
    }
}

enum CubeLUTError: LocalizedError, Equatable {
    case notUTF8
    case missingSize
    case unsupported1D
    case sizeOutOfRange(Int)
    case badLine(Int, String)
    case wrongCount(expected: Int, found: Int)

    var errorDescription: String? {
        switch self {
        case .notUTF8: return "The file is not a text .cube LUT."
        case .missingSize: return "LUT_3D_SIZE is missing."
        case .unsupported1D: return "1D LUTs are not supported. Export a 3D LUT (17, 33 or 65)."
        case .sizeOutOfRange(let n): return "LUT size \(n) is not supported (2…128)."
        case .badLine(let n, let s): return "Line \(n) is not valid: \(s)"
        case .wrongCount(let e, let f): return "Expected \(e) entries, found \(f)."
        }
    }
}

enum CubeLUTParser {

    static let maxSize = 128

    static func parse(data: Data, fallbackTitle: String = "LUT") throws -> CubeLUT {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw CubeLUTError.notUTF8
        }
        return try parse(text: text, fallbackTitle: fallbackTitle)
    }

    static func parse(text: String, fallbackTitle: String = "LUT") throws -> CubeLUT {
        var title = fallbackTitle
        var size: Int?
        var dMin = SIMD3<Float>(repeating: 0)
        var dMax = SIMD3<Float>(repeating: 1)
        var values: [SIMD3<Float>] = []

        var lineNo = 0
        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            lineNo += 1
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if let first = line.first, first.isLetter {
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard let keyword = parts.first?.uppercased() else { continue }
                switch keyword {
                case "TITLE":
                    title = line.dropFirst(5).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                case "LUT_3D_SIZE":
                    guard parts.count >= 2, let n = Int(parts[1]) else { throw CubeLUTError.badLine(lineNo, line) }
                    guard (2...maxSize).contains(n) else { throw CubeLUTError.sizeOutOfRange(n) }
                    size = n
                    values.reserveCapacity(n * n * n)
                case "LUT_1D_SIZE":
                    throw CubeLUTError.unsupported1D
                case "DOMAIN_MIN":
                    dMin = try triple(parts.dropFirst(), lineNo, line)
                case "DOMAIN_MAX":
                    dMax = try triple(parts.dropFirst(), lineNo, line)
                default:
                    continue // LUT_3D_INPUT_RANGE and vendor keywords are ignored safely
                }
                continue
            }

            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            values.append(try triple(parts[...], lineNo, line))
        }

        guard let n = size else { throw CubeLUTError.missingSize }
        guard values.count == n * n * n else { throw CubeLUTError.wrongCount(expected: n * n * n, found: values.count) }
        return CubeLUT(title: title, size: n, domainMin: dMin, domainMax: dMax, values: values)
    }

    private static func triple<S: Collection>(_ parts: S, _ lineNo: Int, _ line: String) throws -> SIMD3<Float>
    where S.Element == Substring {
        let nums = parts.prefix(3).compactMap { Float($0) }
        guard nums.count == 3, parts.count >= 3 else { throw CubeLUTError.badLine(lineNo, line) }
        return SIMD3(nums[0], nums[1], nums[2])
    }
}
