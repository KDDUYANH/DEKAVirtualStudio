//
//  Models.swift
//  Plain Codable value types. These ARE the project file format (see ProjectManager),
//  so every field has a default. ProjectManager merges saved JSON over these defaults, so
//  older project files missing newer keys still load (forward compatible).
//

import Foundation
import CoreGraphics

// MARK: - Color

struct RGBValue: Codable, Equatable, Hashable {
    var r: Float
    var g: Float
    var b: Float
    static let zero = RGBValue(r: 0, g: 0, b: 0)
    static let one  = RGBValue(r: 1, g: 1, b: 1)
    var simd: SIMD3<Float> { SIMD3(r, g, b) }
}

struct RGBAColor: Codable, Equatable, Hashable {
    var r: Float, g: Float, b: Float, a: Float = 1
    static let black = RGBAColor(r: 0, g: 0, b: 0)
    static let white = RGBAColor(r: 1, g: 1, b: 1)
    static let chromaGreen = RGBAColor(r: 0.0, g: 0.69, b: 0.25)
    static let chromaBlue  = RGBAColor(r: 0.0, g: 0.28, b: 0.73)
    var simd: SIMD4<Float> { SIMD4(r, g, b, a) }
    var cgColor: CGColor { CGColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a)) }
}

/// Primary grade. Sliders are normalized −1…1 unless noted; 0 = neutral.
struct ColorSettings: Codable, Equatable {
    var enabled = true
    // Basic
    var exposure: Float = 0        // stops, −3…3
    var contrast: Float = 0
    var highlights: Float = 0
    var shadows: Float = 0
    var blacks: Float = 0
    var whites: Float = 0
    var saturation: Float = 0
    var vibrance: Float = 0
    var temperature: Float = 0     // −1 (cool) … 1 (warm)
    var tint: Float = 0            // −1 (green) … 1 (magenta)
    // Advanced
    var lift = RGBValue.zero       // −0.5…0.5
    var gamma = RGBValue.one       // 0.2…3
    var gain = RGBValue.one        // 0…2
    var offset = RGBValue.zero     // −0.5…0.5
    var liftMaster: Float = 0
    var gammaMaster: Float = 1
    var gainMaster: Float = 1
    var offsetMaster: Float = 0
    var hue: Float = 0             // degrees −180…180
    var midtoneDetail: Float = 0

    static let neutral = ColorSettings()
}

// MARK: - LUT

struct LUTSettings: Codable, Equatable {
    var enabled = false
    var lutID: String? = nil       // LUTLibrary item id
    var intensity: Float = 1
}

// MARK: - Key

enum KeyMode: String, Codable, CaseIterable, Identifiable {
    case off, greenScreen, aiCutout
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return "OFF"
        case .greenScreen: return "GREEN SCREEN"
        case .aiCutout: return "AI CUTOUT"
        }
    }
}

enum KeyColorPreset: String, Codable, CaseIterable, Identifiable {
    case green, blue, custom
    var id: String { rawValue }
}

struct ChromaSettings: Codable, Equatable {
    var preset: KeyColorPreset = .green
    var customColor = RGBAColor.chromaGreen
    var similarity: Float = 0.10     // CbCr distance
    var smoothness: Float = 0.08
    var spill: Float = 0.10
    var edge: Float = 0              // −1 spread … 1 choke
    var feather: Float = 2           // pixels (Gaussian radius)
    var opacity: Float = 1

    var keyColor: RGBAColor {
        switch preset {
        case .green: return .chromaGreen
        case .blue: return .chromaBlue
        case .custom: return customColor
        }
    }
}

enum SegmentationQuality: String, Codable, CaseIterable, Identifiable {
    case fast, balanced, accurate
    var id: String { rawValue }
}

struct SegmentationSettings: Codable, Equatable {
    var quality: SegmentationQuality = .balanced
    var targetFPS: Int = 30          // inference rate (camera may be higher)
    var fallbackToChroma = true      // allowed by thermal / performance manager
}

// MARK: - Background

enum BackgroundKind: String, Codable, CaseIterable, Identifiable {
    case none, solid, gradient, image, video, browser
    var id: String { rawValue }
}

struct BackgroundSettings: Codable, Equatable {
    var kind: BackgroundKind = .gradient
    var colorA = RGBAColor(r: 0.05, g: 0.06, b: 0.10)
    var colorB = RGBAColor(r: 0.16, g: 0.18, b: 0.30)
    var gradientAngle: Float = 90    // degrees
    var assetName: String? = nil     // file in project assets
    var browserURL: String = "https://apple.com"
    var browserFPS: Int = 30
    var scale: Float = 1
    var positionX: Float = 0
    var positionY: Float = 0
    var blur: Float = 0              // radius in pixels at output resolution
    var opacity: Float = 1
    var brightness: Float = 0
    var contrast: Float = 0
    // Composite dressing
    var shadowOpacity: Float = 0
    var shadowOffsetX: Float = 0.01
    var shadowOffsetY: Float = 0.015
    var lightWrap: Float = 0
}

// MARK: - Transform (camera/foreground placement)

struct TransformSettings: Codable, Equatable {
    var scale: Float = 1
    var positionX: Float = 0
    var positionY: Float = 0
}

// MARK: - Graphics

struct LowerThird: Codable, Equatable {
    var enabled = false
    var title = "Live Presenter"
    var subtitle = "D-TEK Studio"
    var accent = RGBAColor(r: 0.93, g: 0.26, b: 0.21)
}

struct TickerSettings: Codable, Equatable {
    var enabled = false
    var text = "D-TEK STUDIO  •  LIVE FROM IPHONE  •"
    var speed: Float = 0.08          // fraction of output width per second
}

enum CornerPosition: String, Codable, CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight
    var id: String { rawValue }
}

struct GraphicsSettings: Codable, Equatable {
    var logoEnabled = false
    var logoAsset: String? = nil
    var logoPosition: CornerPosition = .topRight
    var logoScale: Float = 0.12      // fraction of output width
    var logoOpacity: Float = 1
    var watermarkText: String = ""
    var textEnabled = false
    var text = ""
    var textSize: Float = 64
    var lowerThird = LowerThird()
    var ticker = TickerSettings()
    var clockEnabled = false
    var countdownEnabled = false
    var countdownTarget: Date? = nil
}

// MARK: - Scene

enum TransitionKind: String, Codable, CaseIterable, Identifiable {
    case cut, fade
    var id: String { rawValue }
}

struct SceneModel: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var color = ColorSettings()
    var lut = LUTSettings()
    var keyMode: KeyMode = .off
    var chroma = ChromaSettings()
    var segmentation = SegmentationSettings()
    var background = BackgroundSettings()
    var graphics = GraphicsSettings()
    var transform = TransformSettings()

    static func defaultScenes() -> [SceneModel] {
        // Only 1 primary main scene by default. Extra scenes are created on-demand using (+) button.
        var main = SceneModel(name: "Main Scene")
        main.keyMode = .greenScreen
        return [main]
    }
}

// MARK: - Output / camera

enum StreamDestination: String, Codable, CaseIterable, Identifiable {
    case srtServer = "SRT SERVER"
    case rtmpServer = "RTMP / LIVE STREAM"
    case dolbyMillicast = "DOLBY MILLICAST"
    var id: String { rawValue }
}

enum Resolution: String, Codable, CaseIterable, Identifiable {
    case hd720 = "720p", hd1080 = "1080p", uhd4k = "4K"
    var id: String { rawValue }
    var size: CGSize {
        switch self {
        case .hd720: return CGSize(width: 1280, height: 720)
        case .hd1080: return CGSize(width: 1920, height: 1080)
        case .uhd4k: return CGSize(width: 3840, height: 2160)
        }
    }
}

struct OutputSettings: Codable, Equatable {
    var preset: QualityPresetID = .mobile
    var resolution: Resolution = .hd1080
    var fps: Int = 30
    var videoBitrateKbps: Int = 4000
    var minVideoBitrateKbps: Int = 1500
    var audioBitrateKbps: Int = 128
    var videoCodec: String = "h264"
    var streamName: String = "cam1"
    var accountID: String = ""
    var region: String = "auto"
    var transition: TransitionKind = .fade
    var transitionDuration: Double = 0.5
    var cleanFeedLiveOutput: Bool = false

    // Destination selector: SRT Server, RTMP, or Dolby OptiView (Millicast)
    var destination: StreamDestination = .srtServer

    // SRT Server Settings (Publishing to MediaMTX / vMix / OBS)
    var srtHost: String = "192.168.1.100"
    var srtPort: Int = 9000
    var srtStreamId: String = "publish:cam1"
    var srtLatencyMs: Int = 200
    var srtPassphrase: String = ""

    // RTMP Server Settings (YouTube, TikTok, Facebook, Twitch, Custom RTMP)
    var rtmpURL: String = "rtmp://a.rtmp.youtube.com/live2"
    var rtmpStreamKey: String = ""

    // Dolby OptiView (Millicast) Settings
    var dolbyEndpoint: String = "live-srt.millicast.com"
    var dolbyPort: Int = 9000
    var dolbyStreamName: String = "dtek-studio"
    var dolbyPublishingToken: String = ""

    // SRT Input (Return Program Feed from vMix / MediaMTX)
    var srtReturnEnabled: Bool = false
    var srtReturnHost: String = ""
    var srtReturnPort: Int = 9000
    var srtReturnStreamId: String = "read:program"

    var publishURLString: String {
        switch destination {
        case .srtServer:
            let host = srtHost.trimmingCharacters(in: .whitespacesAndNewlines)
            let streamId = srtStreamId.trimmingCharacters(in: .whitespacesAndNewlines)
            var s = "srt://\(host.isEmpty ? "127.0.0.1" : host):\(srtPort)?mode=caller&latency=\(srtLatencyMs)"
            if !streamId.isEmpty { s += "&streamid=\(streamId)" }
            if !srtPassphrase.isEmpty { s += "&passphrase=\(srtPassphrase)" }
            return s
        case .rtmpServer:
            let u = rtmpURL.trimmingCharacters(in: .whitespacesAndNewlines)
            return u.isEmpty ? "rtmp://a.rtmp.youtube.com/live2" : u
        case .dolbyMillicast:
            let endpoint = dolbyEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            let streamName = dolbyStreamName.trimmingCharacters(in: .whitespacesAndNewlines)
            let token = dolbyPublishingToken.trimmingCharacters(in: .whitespacesAndNewlines)
            var s = "srt://\(endpoint.isEmpty ? "live-srt.millicast.com" : endpoint):\(dolbyPort)?mode=caller&latency=\(srtLatencyMs)"
            if !streamName.isEmpty { s += "&streamid=\(streamName)" }
            if !token.isEmpty { s += "&passphrase=\(token)" }
            return s
        }
    }

    var publishStreamKey: String {
        switch destination {
        case .rtmpServer:
            return rtmpStreamKey.trimmingCharacters(in: .whitespacesAndNewlines)
        case .srtServer:
            return srtStreamId.trimmingCharacters(in: .whitespacesAndNewlines)
        case .dolbyMillicast:
            return dolbyStreamName.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    var srtPublishURLString: String {
        publishURLString
    }

    var srtReturnURLString: String {
        let targetHost = srtReturnHost.isEmpty ? srtHost : srtReturnHost
        let host = targetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let streamId = srtReturnStreamId.trimmingCharacters(in: .whitespacesAndNewlines)
        var s = "srt://\(host.isEmpty ? "127.0.0.1" : host):\(srtReturnPort)?mode=caller&latency=\(srtLatencyMs)"
        if !streamId.isEmpty { s += "&streamid=\(streamId)" }
        if !srtPassphrase.isEmpty { s += "&passphrase=\(srtPassphrase)" }
        return s
    }

    var publishURL: String? {
        let s = publishURLString
        return s.isEmpty ? nil : s
    }

    var srtPublishURL: String? {
        publishURL
    }

    var srtReturnURL: String? {
        guard srtReturnEnabled else { return nil }
        return srtReturnURLString
    }
}

enum LensKind: String, Codable, CaseIterable, Identifiable {
    case ultraWide, wide, telephoto
    var id: String { rawValue }
}

enum CameraPositionSetting: String, Codable { case back, front }

enum ControlMode: String, Codable, CaseIterable, Identifiable {
    case auto = "AUTO", lock = "LOCK", manual = "MANUAL"
    var id: String { rawValue }
}

struct CameraSettings: Codable, Equatable {
    var position: CameraPositionSetting = .back
    var zoom: Float = 1
    var exposureMode: ControlMode = .auto
    var iso: Float = 100
    var shutterDenominator: Float = 60   // 1/x s
    var exposureBias: Float = 0
    var focusMode: ControlMode = .auto
    var lensPosition: Float = 0.5
    var whiteBalanceMode: ControlMode = .auto
    var whiteBalanceKelvin: Float = 5600
    var whiteBalanceTint: Float = 0
    var torch: Float = 0
    var stabilization = false            // off by default: adds latency
}

// MARK: - Project

struct StudioProject: Codable, Equatable, Identifiable {
    static let currentSchema = 1
    var schema = StudioProject.currentSchema
    var id = UUID()
    var name: String
    var createdAt = Date()
    var modifiedAt = Date()
    var camera = CameraSettings()
    var scenes: [SceneModel] = SceneModel.defaultScenes()
    var activeSceneID: UUID?
    var output = OutputSettings()
    var audio = AudioSettings()

    init(name: String) {
        self.name = name
        self.activeSceneID = scenes.first?.id
    }
}

struct AudioSettings: Codable, Equatable {
    var muted = false
    var gainDB: Float = 0                // −24…+24
    var compressorEnabled = true
    var compressorThresholdDB: Float = -18
    var compressorRatio: Float = 3       // informational; AUDynamicsProcessor uses headroom
    var limiterEnabled = true
    var limiterCeilingDB: Float = -1
    var preferredInputUID: String? = nil
}
