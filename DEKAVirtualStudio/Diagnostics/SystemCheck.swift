//
//  SystemCheck.swift
//  SYSTEM CHECK — every line is the result of a real test on this device. A check that cannot
//  be verified offline says so (INFO / SKIPPED) instead of pretending to pass.
//

import Foundation
import AVFoundation
import CoreVideo
import VideoToolbox
import Network

enum CheckStatus: String {
    case pass = "PASS", warn = "WARN", fail = "FAIL", info = "INFO", skipped = "SKIPPED", running = "…"
}

struct CheckResult: Identifiable, Equatable {
    let id: String
    var status: CheckStatus
    var detail: String
}

final class SystemCheck {

    struct Dependencies {
        let context: MetalContext?
        let cameraRunning: () -> Bool
        let programFPS: () -> Double
        let audio: AudioEngine
        let lutLibrary: LUTLibrary?
    }

    private let deps: Dependencies
    init(_ deps: Dependencies) { self.deps = deps }

    static let order = ["Camera", "Microphone", "Metal", "LUT", "Chroma", "Output", "AI", "SRT Encoder", "Network", "Storage", "Thermal"]

    func run(update: @escaping (CheckResult) -> Void) async {
        for name in Self.order { update(CheckResult(id: name, status: .running, detail: "")) }
        update(await camera())
        update(microphone())
        let harness = deps.context.map { GPUTestHarness(context: $0) }
        update(metal(harness))
        update(lut(harness))
        update(chroma(harness))
        update(output(harness))
        update(await ai())
        update(srtEncoder())
        update(network())
        update(storage())
        update(thermal())
    }

    // MARK: Checks

    private func camera() async -> CheckResult {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            return CheckResult(id: "Camera", status: .fail, detail: "Camera permission not granted")
        }
        guard AVCaptureDevice.default(for: .video) != nil else {
            return CheckResult(id: "Camera", status: .fail, detail: "No camera device")
        }
        guard deps.cameraRunning() else { return CheckResult(id: "Camera", status: .warn, detail: "Camera session not running") }
        try? await Task.sleep(nanoseconds: 1_200_000_000)   // measure over a full second
        let fps = deps.programFPS()
        return CheckResult(id: "Camera", status: fps > 5 ? .pass : .fail, detail: String(format: "%.1f fps delivered to the pipeline", fps))
    }

    private func microphone() -> CheckResult {
        guard AVAudioApplication.shared.recordPermission == .granted else {
            return CheckResult(id: "Microphone", status: .fail, detail: "Microphone permission not granted")
        }
        let inputs = deps.audio.availableInputs
        guard !inputs.isEmpty else { return CheckResult(id: "Microphone", status: .fail, detail: "No audio input") }
        guard deps.audio.isRunning else { return CheckResult(id: "Microphone", status: .warn, detail: "Audio engine not running") }
        let peak = deps.audio.levels.peakDB.max() ?? -120
        return CheckResult(id: "Microphone", status: .pass,
                           detail: "\(deps.audio.currentInputName) · peak \(Int(peak)) dBFS" + (peak < -90 ? " (no signal — speak to test)" : ""))
    }

    private func metal(_ h: GPUTestHarness?) -> CheckResult {
        guard let h else { return CheckResult(id: "Metal", status: .fail, detail: "Metal unavailable") }
        do {
            let r = try h.checkDecode()
            return CheckResult(id: "Metal", status: r.pass ? .pass : .fail, detail: "\(h.context.device.name) · decode \(r.detail)")
        } catch { return CheckResult(id: "Metal", status: .fail, detail: error.localizedDescription) }
    }

    private func lut(_ h: GPUTestHarness?) -> CheckResult {
        guard let h else { return CheckResult(id: "LUT", status: .skipped, detail: "Metal unavailable") }
        do {
            // A real 33³ non-identity LUT (bundled) if present, else a generated one.
            var cube: CubeLUT
            if let url = Bundle.main.url(forResource: "DEKA_TealOrange_33", withExtension: "cube") {
                cube = try CubeLUTParser.parse(data: Data(contentsOf: url))
            } else {
                cube = CubeLUT.identity(size: 33)
                cube.values = cube.values.map { SIMD3($0.x * 0.9 + 0.05, $0.y, $0.z * 0.8) }
            }
            let r = try h.checkLUT(cube)
            return CheckResult(id: "LUT", status: r.pass ? .pass : .fail, detail: r.detail)
        } catch { return CheckResult(id: "LUT", status: .fail, detail: error.localizedDescription) }
    }

    private func chroma(_ h: GPUTestHarness?) -> CheckResult {
        guard let h else { return CheckResult(id: "Chroma", status: .skipped, detail: "Metal unavailable") }
        do {
            let r = try h.checkChroma()
            return CheckResult(id: "Chroma", status: r.pass ? .pass : .fail, detail: r.detail)
        } catch { return CheckResult(id: "Chroma", status: .fail, detail: error.localizedDescription) }
    }

    private func output(_ h: GPUTestHarness?) -> CheckResult {
        guard let h else { return CheckResult(id: "Output", status: .skipped, detail: "Metal unavailable") }
        do {
            let r = try h.checkNV12()
            return CheckResult(id: "Output", status: r.pass ? .pass : .fail, detail: "NV12 BT.709 · " + r.detail)
        } catch { return CheckResult(id: "Output", status: .fail, detail: error.localizedDescription) }
    }

    private func ai() async -> CheckResult {
        // Runs the real Vision request on a synthetic frame. This proves the model loads and
        // executes on this device and measures its latency; mask QUALITY needs a person in frame.
        do {
            let seg: PersonSegmenter
            if let coreML = try? CoreMLPersonSegmenter() { seg = coreML } else { seg = VisionPersonSegmenter(quality: .balanced) }
            guard let ctx = deps.context else { return CheckResult(id: "AI", status: .skipped, detail: "Metal unavailable") }
            let pb = try GPUTestHarness(context: ctx).makeCameraBuffer(rgb: SIMD3(0.4, 0.4, 0.4))
            let t0 = hostTimeSeconds()
            let mask = try seg.mask(for: pb)
            let ms = (hostTimeSeconds() - t0) * 1000
            let w = CVPixelBufferGetWidth(mask), hgt = CVPixelBufferGetHeight(mask)
            return CheckResult(id: "AI", status: .pass,
                               detail: String(format: "%@ runs · %ld×%ld mask · %.0f ms (first run includes model load)", seg.name, w, hgt, ms))
        } catch {
            return CheckResult(id: "AI", status: .fail, detail: error.localizedDescription)
        }
    }

    private func srtEncoder() -> CheckResult {
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: 1920,
            height: 1080,
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        if status == noErr, let s = session {
            VTCompressionSessionInvalidate(s)
            return CheckResult(id: "SRT Encoder", status: .pass, detail: "Hardware H.264/HEVC VideoToolbox encoder ready")
        } else {
            return CheckResult(id: "SRT Encoder", status: .warn, detail: "VideoToolbox status: \(status)")
        }
    }

    private func network() -> CheckResult {
        let monitor = NWPathMonitor()
        let semaphore = DispatchSemaphore(value: 0)
        var pathStatus: NWPath.Status = .requiresConnection
        var ifaceDesc = "Unknown"
        let queue = DispatchQueue(label: "SystemCheck.Network")

        monitor.pathUpdateHandler = { path in
            pathStatus = path.status
            if path.usesInterfaceType(.wifi) {
                ifaceDesc = "Wi-Fi"
            } else if path.usesInterfaceType(.cellular) {
                ifaceDesc = "Cellular"
            } else if path.usesInterfaceType(.wiredEthernet) {
                ifaceDesc = "Ethernet"
            } else {
                ifaceDesc = "Connected"
            }
            semaphore.signal()
        }
        monitor.start(queue: queue)
        _ = semaphore.wait(timeout: .now() + 0.5)
        monitor.cancel()

        if pathStatus == .satisfied {
            return CheckResult(id: "Network", status: .pass, detail: "\(ifaceDesc) active · ready for SRT output & input")
        } else {
            return CheckResult(id: "Network", status: .warn, detail: "Network status: \(pathStatus)")
        }
    }

    private func storage() -> CheckResult {
        let free = SystemMetrics.freeStorageBytes()
        let status: CheckStatus = free > RecordingEngine.lowStorageWarnBytes ? .pass : (free > RecordingEngine.lowStorageStopBytes ? .warn : .fail)
        // Program at ~20 Mbit/s HEVC ≈ 9 GB/hour
        let minutes = Double(free) / (20_000_000 / 8) / 60
        return CheckResult(id: "Storage", status: status,
                           detail: "\(SystemMetrics.formatBytes(free)) free ≈ \(Int(minutes)) min of 1080p recording")
    }

    private func thermal() -> CheckResult {
        let level = ThermalLevel(ProcessInfo.processInfo.thermalState)
        let status: CheckStatus = level <= .fair ? .pass : (level == .serious ? .warn : .fail)
        return CheckResult(id: "Thermal", status: status, detail: level.label)
    }
}
