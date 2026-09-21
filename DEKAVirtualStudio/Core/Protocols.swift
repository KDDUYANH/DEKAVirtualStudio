//
//  Protocols.swift
//  Module boundaries. Engines talk through these, never through SwiftUI views.
//

import Foundation
import CoreMedia
import CoreVideo
import Metal

/// One camera frame as delivered by AVFoundation (no copies: the pixel buffer is retained).
struct CameraFrame {
    let pixelBuffer: CVPixelBuffer
    let presentationTime: CMTime
    let hostTime: Double
}

/// Receives camera frames on the capture queue.
protocol CameraFrameConsumer: AnyObject {
    func camera(didOutput frame: CameraFrame)
    func cameraDidDropFrame(reason: String)
}

/// The finished program frame (NV12, encoder native) + its GPU texture.
struct MasterFrame {
    let pixelBuffer: CVPixelBuffer      // NV12 BT.709 video range, IOSurface backed
    let texture: MTLTexture             // RGBA master (for preview / diagnostics)
    let presentationTime: CMTime
    let sourceCamera: CVPixelBuffer     // untouched camera buffer (CAMERA recording mode)
}

/// Anything that consumes the finished program (stream, recorder, preview).
protocol MasterFrameSink: AnyObject {
    func consume(master: MasterFrame)
}

/// Processed program audio: 16-bit interleaved PCM with a host-clock timestamp
/// (the same clock as camera frames, so audio and video stay in sync everywhere).
struct AudioChunk {
    let samples: [Int16]          // interleaved
    let channels: Int
    let sampleRate: Double
    let frameCount: Int
    let presentationTime: CMTime
}

protocol AudioSampleSink: AnyObject {
    func consume(audio: AudioChunk)
}

/// Transport-agnostic publisher interface; SRTEngine is the implementation.
protocol StreamPublisher: AnyObject, MasterFrameSink, AudioSampleSink {
    var state: StreamState { get }
    func start(configuration: StreamConfiguration) async throws
    func stop() async
}

enum StreamState: Equatable {
    case off
    case authorizing
    case connecting
    case live
    case reconnecting(attempt: Int)
    case failed(String)

    var isOnAir: Bool {
        switch self {
        case .live, .reconnecting: return true
        default: return false
        }
    }
    var label: String {
        switch self {
        case .off: return "STREAM OFF"
        case .authorizing: return "AUTHORIZING"
        case .connecting: return "CONNECTING"
        case .live: return "LIVE"
        case .reconnecting(let n): return "RECONNECTING \(n)"
        case .failed: return "FAILED"
        }
    }
}

struct StreamConfiguration: Equatable {
    var resolution: Resolution
    var fps: Int
    var videoBitrateKbps: Int
    var minVideoBitrateKbps: Int
    var audioBitrateKbps: Int
    var videoCodec: String
    var streamName: String
    var srtPublishURL: String = ""
    var srtReturnURL: String? = nil
    var streamKey: String = ""
}
