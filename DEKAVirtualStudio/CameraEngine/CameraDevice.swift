//
//  CameraDevice.swift
//  What the current camera can really do. The UI only ever shows options listed here.
//

import AVFoundation

struct CaptureMode: Hashable, Identifiable, Codable {
    let resolution: Resolution
    let fps: Int
    var id: String { "\(resolution.rawValue)\(fps)" }
    var label: String { "\(resolution.rawValue)\(fps)" }
}

struct LensOption: Hashable, Identifiable {
    let kind: LensKind
    let zoomFactor: CGFloat        // device zoom factor to set
    let displayLabel: String       // what the operator sees, e.g. "0.5×"
    var id: LensKind { kind }
}

struct CameraCapabilities: Equatable {
    var deviceName = ""
    var position: CameraPositionSetting = .back
    var modes: [CaptureMode] = []
    var lenses: [LensOption] = []
    var minZoom: CGFloat = 1
    var maxZoom: CGFloat = 1
    var displayZoomMultiplier: CGFloat = 1   // device zoom / multiplier = marketing zoom (1× = wide)
    var supportsManualExposure = false
    var supportsExposureLock = false
    var isoRange: ClosedRange<Float> = 100...100
    var shutterRange: ClosedRange<Float> = 30...8000   // 1/x denominators
    var supportsWhiteBalanceLock = false
    var supportsManualFocus = false
    var supportsFocusLock = false
    var hasTorch = false

    func supports(_ mode: CaptureMode) -> Bool { modes.contains(mode) }
}

/// Snapshot of live camera readouts for telemetry (read at a few Hz, never per frame on main).
struct CameraReadout: Equatable {
    var iso: Float = 0
    var shutterDenominator: Float = 0
    var whiteBalanceKelvin: Float = 0
    var lensPosition: Float = 0
    var zoomDisplay: CGFloat = 1
    var activeMode: CaptureMode?
}
