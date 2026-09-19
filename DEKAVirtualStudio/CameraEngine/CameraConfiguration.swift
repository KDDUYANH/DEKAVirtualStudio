//
//  CameraConfiguration.swift
//  Pure format-selection logic (unit tested). Given the formats a device reports, pick the one
//  that delivers the requested resolution + frame rate at the lowest cost.
//

import Foundation
import CoreMedia

struct FormatCandidate: Equatable {
    let index: Int                 // index into device.formats
    let width: Int32
    let height: Int32
    let maxFPS: Double
    let fullRange: Bool            // '420f' vs '420v'
    let isBinned: Bool             // binned formats are cooler / lower power at same output
    let isVideoHDR: Bool
}

enum CameraFormatSelector {

    /// Resolution buckets the studio produces. Camera must deliver exactly this size.
    static func matches(_ c: FormatCandidate, _ resolution: Resolution) -> Bool {
        Int(c.width) == Int(resolution.size.width) && Int(c.height) == Int(resolution.size.height)
    }

    /// Best format for a mode, or nil if the device cannot do it (then the mode is hidden).
    static func select(from candidates: [FormatCandidate], resolution: Resolution, fps: Int) -> FormatCandidate? {
        let usable = candidates.filter { matches($0, resolution) && $0.maxFPS + 0.01 >= Double(fps) }
        // Preference: full range (better keying precision) > binned (thermals) > no HDR (latency)
        // > lowest max fps that still satisfies (sensor runs less hot).
        return usable.sorted { a, b in
            if a.fullRange != b.fullRange { return a.fullRange }
            if a.isBinned != b.isBinned { return a.isBinned }
            if a.isVideoHDR != b.isVideoHDR { return !a.isVideoHDR }
            return a.maxFPS < b.maxFPS
        }.first
    }

    /// Every studio mode the device can actually run.
    static func supportedModes(from candidates: [FormatCandidate]) -> [CaptureMode] {
        var modes: [CaptureMode] = []
        for res in [Resolution.hd720, .hd1080, .uhd4k] {
            for fps in [30, 60] where select(from: candidates, resolution: res, fps: fps) != nil {
                modes.append(CaptureMode(resolution: res, fps: fps))
            }
        }
        return modes
    }
}
