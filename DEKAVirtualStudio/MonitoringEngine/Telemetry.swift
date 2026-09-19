//
//  Telemetry.swift
//  One snapshot the UI renders at 2 Hz. Every value is measured; nothing is estimated for show.
//

import Foundation
import CoreGraphics

struct TelemetrySnapshot: Equatable {
    var streamState: StreamState = .off
    var mode: String = "—"                 // e.g. 1080p60
    var programFPS: Double = 0
    var gpuMs: Double = 0
    var frameBudgetMs: Double = 33.3
    var droppedFrames: Int = 0
    var stream = StreamStats()
    var audio = AudioLevels()
    var thermal: ThermalLevel = .nominal
    var batteryPercent: Int?
    var charging = false
    var memoryMB: Double = 0
    var ai = SegmentationStats()
    var aiActive = false
    var recording = RecordingStatus()
    var camera = CameraReadout()

    /// GPU load as a share of the frame budget (a real measurement: GPU start→end per frame).
    var gpuLoad: Double { frameBudgetMs > 0 ? min(gpuMs / frameBudgetMs, 9.99) : 0 }
}
