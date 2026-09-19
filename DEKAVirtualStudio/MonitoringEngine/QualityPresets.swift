//
//  QualityPresets.swift
//  MOBILE / BROADCAST / LOW BANDWIDTH. A preset is only offered when the camera really
//  supports its mode; otherwise the nearest supported mode is proposed with a clear reason.
//

import Foundation

enum QualityPresetID: String, Codable, CaseIterable, Identifiable {
    case mobile, broadcast, lowBandwidth, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .mobile: return "MOBILE"
        case .broadcast: return "BROADCAST"
        case .lowBandwidth: return "LOW BANDWIDTH"
        case .custom: return "CUSTOM"
        }
    }
}

struct QualityPreset: Equatable {
    let id: QualityPresetID
    let mode: CaptureMode
    let targetKbps: Int
    let minKbps: Int
    let maxKbps: Int
    let audioKbps: Int

    static let mobile = QualityPreset(id: .mobile, mode: CaptureMode(resolution: .hd1080, fps: 30),
                                      targetKbps: 4000, minKbps: 3000, maxKbps: 5000, audioKbps: 128)
    static let broadcast = QualityPreset(id: .broadcast, mode: CaptureMode(resolution: .hd1080, fps: 60),
                                         targetKbps: 6500, minKbps: 5000, maxKbps: 8000, audioKbps: 160)
    static let lowBandwidth = QualityPreset(id: .lowBandwidth, mode: CaptureMode(resolution: .hd720, fps: 30),
                                            targetKbps: 2000, minKbps: 1500, maxKbps: 2500, audioKbps: 96)

    static func preset(_ id: QualityPresetID) -> QualityPreset? {
        switch id {
        case .mobile: return .mobile
        case .broadcast: return .broadcast
        case .lowBandwidth: return .lowBandwidth
        case .custom: return nil
        }
    }

    /// Resolution against real capabilities. Returns the mode to use and, if different, why.
    static func resolve(_ preset: QualityPreset, supported: [CaptureMode]) -> (mode: CaptureMode?, note: String?) {
        if supported.contains(preset.mode) { return (preset.mode, nil) }
        // Same resolution at a lower frame rate first, then other resolutions (largest first).
        let sameResolution = supported
            .filter { $0.resolution == preset.mode.resolution && $0.fps < preset.mode.fps }
            .sorted { $0.fps > $1.fps }
        let otherResolutions = supported
            .filter { $0.resolution != preset.mode.resolution && $0.fps <= preset.mode.fps }
            .sorted { a, b in
                if a.resolution.size.width != b.resolution.size.width { return a.resolution.size.width > b.resolution.size.width }
                return a.fps > b.fps
            }
        let fallbacks = sameResolution + otherResolutions
        guard let fb = fallbacks.first else { return (nil, "This camera cannot run \(preset.mode.label).") }
        return (fb, "\(preset.mode.label) is not supported by this camera; using \(fb.label).")
    }

    func apply(to output: inout OutputSettings) {
        output.preset = id
        output.resolution = mode.resolution
        output.fps = mode.fps
        output.videoBitrateKbps = targetKbps
        output.minVideoBitrateKbps = minKbps
        output.audioBitrateKbps = audioKbps
    }
}
