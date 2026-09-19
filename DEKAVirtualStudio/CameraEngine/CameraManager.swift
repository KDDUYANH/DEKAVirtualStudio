//
//  CameraManager.swift
//  AVCaptureSession → CMSampleBuffer → CVPixelBuffer (no copy) → CameraFrameConsumer.
//
//  Threads:
//   • sessionQueue: all session/device configuration (never the main thread)
//   • videoQueue:   frame delivery; the consumer encodes GPU work here and returns quickly
//

import AVFoundation
import UIKit

final class CameraManager: NSObject, @unchecked Sendable {

    enum CameraError: LocalizedError {
        case notAuthorized, noDevice, cannotAddInput, cannotAddOutput, modeUnsupported(CaptureMode)
        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "Camera access is not allowed. Enable it in Settings."
            case .noDevice: return "No camera found."
            case .cannotAddInput: return "Camera input could not be added."
            case .cannotAddOutput: return "Video output could not be added."
            case .modeUnsupported(let m): return "\(m.label) is not supported by this camera."
            }
        }
    }

    let session = AVCaptureSession()
    let videoQueue = DispatchQueue(label: "deka.camera.video", qos: .userInteractive)
    private let sessionQueue = DispatchQueue(label: "deka.camera.session", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private(set) var device: AVCaptureDevice?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    weak var consumer: CameraFrameConsumer?

    /// Published to the controller (called on the session queue).
    var onCapabilities: ((CameraCapabilities) -> Void)?
    var onRotate180: ((Bool) -> Void)?
    var onRuntimeError: ((String) -> Void)?

    private(set) var capabilities = CameraCapabilities()
    private(set) var activeMode: CaptureMode?
    private(set) var isFrontCamera = false

    // MARK: Authorization

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    // MARK: Lifecycle

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError(_:)),
                                               name: AVCaptureSession.runtimeErrorNotification, object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded(_:)),
                                               name: AVCaptureSession.interruptionEndedNotification, object: session)
    }

    func configure(position: CameraPositionSetting, mode: CaptureMode) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.configureOnQueue(position: position, mode: mode)
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    func start() {
        sessionQueue.async {
            guard !self.session.isRunning else { return }
            self.session.startRunning()
            Log.camera.info("Session started")
        }
    }

    func stop() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
            Log.camera.info("Session stopped")
        }
    }

    var isRunning: Bool { session.isRunning }

    // MARK: Configuration

    private func discoverDevice(position: CameraPositionSetting) -> AVCaptureDevice? {
        let pos: AVCaptureDevice.Position = (position == .front) ? .front : .back
        let types: [AVCaptureDevice.DeviceType] = (position == .front)
            ? [.builtInWideAngleCamera]
            : [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: pos)
        // DiscoverySession returns devices in the order of `deviceTypes`: the most capable first.
        for type in types {
            if let d = discovery.devices.first(where: { $0.deviceType == type }) { return d }
        }
        return nil
    }

    private func candidates(for device: AVCaptureDevice) -> [FormatCandidate] {
        device.formats.enumerated().compactMap { index, format in
            let desc = format.formatDescription
            let subtype = CMFormatDescriptionGetMediaSubType(desc)
            guard subtype == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                    || subtype == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange else { return nil }
            let dims = CMVideoFormatDescriptionGetDimensions(desc)
            let maxFPS = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            return FormatCandidate(index: index,
                                   width: dims.width, height: dims.height,
                                   maxFPS: maxFPS,
                                   fullRange: subtype == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                   isBinned: format.isVideoBinned,
                                   isVideoHDR: format.isVideoHDRSupported)
        }
    }

    private func configureOnQueue(position: CameraPositionSetting, mode: CaptureMode) throws {
        guard let device = discoverDevice(position: position) else { throw CameraError.noDevice }
        let cands = candidates(for: device)
        guard let chosen = CameraFormatSelector.select(from: cands, resolution: mode.resolution, fps: mode.fps) else {
            throw CameraError.modeUnsupported(mode)
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .inputPriority
        // The session must not reconfigure AVAudioSession: AudioEngine owns audio.
        session.automaticallyConfiguresApplicationAudioSession = false

        if let input { session.removeInput(input) }
        let newInput = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(newInput) else { throw CameraError.cannotAddInput }
        session.addInput(newInput)
        input = newInput

        if !session.outputs.contains(videoOutput) {
            guard session.canAddOutput(videoOutput) else { throw CameraError.cannotAddOutput }
            session.addOutput(videoOutput)
        }
        videoOutput.alwaysDiscardsLateVideoFrames = true
        let pixelFormat = chosen.fullRange ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                                           : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat]
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)

        try device.lockForConfiguration()
        device.activeFormat = device.formats[chosen.index]
        let duration = CMTime(value: 1, timescale: CMTimeScale(mode.fps))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { device.whiteBalanceMode = .continuousAutoWhiteBalance }
        // Start on the 1× (wide) lens for virtual multi-camera devices.
        let wideFactor = device.virtualDeviceSwitchOverVideoZoomFactors.first.map { CGFloat(truncating: $0) } ?? 1
        let hasUltraWide = device.constituentDevices.contains { $0.deviceType == .builtInUltraWideCamera }
        device.videoZoomFactor = hasUltraWide ? wideFactor : 1
        device.unlockForConfiguration()

        if let connection = videoOutput.connection(with: .video) {
            // Stabilisation adds a frame+ of latency; live production prefers it off.
            if connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .off }
            connection.isVideoMirrored = false   // mirroring is done in the shader when wanted
        }

        self.device = device
        self.isFrontCamera = (position == .front)
        self.activeMode = mode
        self.capabilities = makeCapabilities(device: device, candidates: cands, position: position)
        observeRotation(device: device)
        onCapabilities?(capabilities)
        Log.camera.info("Configured \(device.localizedName, privacy: .public) \(mode.label, privacy: .public)")
    }

    private func makeCapabilities(device: AVCaptureDevice, candidates: [FormatCandidate],
                                  position: CameraPositionSetting) -> CameraCapabilities {
        var caps = CameraCapabilities()
        caps.deviceName = device.localizedName
        caps.position = position
        caps.modes = CameraFormatSelector.supportedModes(from: candidates)

        let switchOver = device.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
        let constituents = device.constituentDevices.map(\.deviceType)
        let hasUltraWide = constituents.contains(.builtInUltraWideCamera)
        let hasTele = constituents.contains(.builtInTelephotoCamera)
        let multiplier: CGFloat = hasUltraWide ? (switchOver.first ?? 2) : 1
        caps.displayZoomMultiplier = multiplier

        var lenses: [LensOption] = []
        if hasUltraWide { lenses.append(LensOption(kind: .ultraWide, zoomFactor: 1, displayLabel: Self.zoomLabel(1 / multiplier))) }
        let wideFactor: CGFloat = hasUltraWide ? multiplier : 1
        lenses.append(LensOption(kind: .wide, zoomFactor: wideFactor, displayLabel: "1×"))
        if hasTele, let teleFactor = switchOver.last, teleFactor > wideFactor {
            lenses.append(LensOption(kind: .telephoto, zoomFactor: teleFactor, displayLabel: Self.zoomLabel(teleFactor / multiplier)))
        }
        caps.lenses = lenses
        caps.minZoom = device.minAvailableVideoZoomFactor
        caps.maxZoom = min(device.maxAvailableVideoZoomFactor, 10 * multiplier)

        let format = device.activeFormat
        caps.supportsManualExposure = device.isExposureModeSupported(.custom)
        caps.supportsExposureLock = device.isExposureModeSupported(.locked)
        caps.isoRange = format.minISO...format.maxISO
        let minDen = Float(1 / max(format.maxExposureDuration.seconds, 1e-6))
        let maxDen = Float(1 / max(format.minExposureDuration.seconds, 1e-6))
        caps.shutterRange = min(minDen, maxDen)...max(minDen, maxDen)
        caps.supportsWhiteBalanceLock = device.isWhiteBalanceModeSupported(.locked)
        caps.supportsManualFocus = device.isLockingFocusWithCustomLensPositionSupported
        caps.supportsFocusLock = device.isFocusModeSupported(.locked)
        caps.hasTorch = device.hasTorch && device.isTorchAvailable
        return caps
    }

    private static func zoomLabel(_ z: CGFloat) -> String {
        z < 1 ? String(format: "%.1f×", z) : String(format: "%.0f×", z.rounded())
    }

    private func observeRotation(device: AVCaptureDevice) {
        rotationObservation = nil
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        rotationCoordinator = coordinator
        let report: (CGFloat) -> Void = { [weak self] angle in
            // Buffers stay sensor-native (no rotation cost). 0° = landscape right, 180° = landscape left.
            // Portrait angles are ignored: the studio is a landscape-only production camera.
            let a = angle.truncatingRemainder(dividingBy: 360)
            if abs(a - 180) < 1 { self?.onRotate180?(true) }
            else if abs(a) < 1 { self?.onRotate180?(false) }
        }
        report(coordinator.videoRotationAngleForHorizonLevelCapture)
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { c, _ in
            report(c.videoRotationAngleForHorizonLevelCapture)
        }
    }

    // MARK: Manual controls (all on the session queue)

    func apply(_ settings: CameraSettings) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                self.applyExposure(settings, device)
                self.applyFocus(settings, device)
                self.applyWhiteBalance(settings, device)
                self.applyTorch(settings, device)
                let target = CGFloat(settings.zoom) * self.capabilities.displayZoomMultiplier
                device.videoZoomFactor = min(max(target, self.capabilities.minZoom), self.capabilities.maxZoom)
            } catch {
                Log.camera.error("lockForConfiguration failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func applyExposure(_ s: CameraSettings, _ d: AVCaptureDevice) {
        switch s.exposureMode {
        case .auto:
            if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure }
            let bias = min(max(s.exposureBias, d.minExposureTargetBias), d.maxExposureTargetBias)
            d.setExposureTargetBias(bias, completionHandler: nil)
        case .lock:
            if d.isExposureModeSupported(.locked) { d.exposureMode = .locked }
        case .manual:
            guard d.isExposureModeSupported(.custom) else { return }
            let f = d.activeFormat
            let iso = min(max(s.iso, f.minISO), f.maxISO)
            var duration = CMTime(seconds: 1.0 / Double(max(s.shutterDenominator, 1)), preferredTimescale: 1_000_000)
            // Clamp to the sensor range AND to the frame duration (otherwise fps would drop).
            let frame = d.activeVideoMinFrameDuration
            if CMTimeCompare(duration, f.minExposureDuration) < 0 { duration = f.minExposureDuration }
            if CMTimeCompare(duration, f.maxExposureDuration) > 0 { duration = f.maxExposureDuration }
            if CMTimeCompare(duration, frame) > 0 { duration = frame }
            d.setExposureModeCustom(duration: duration, iso: iso, completionHandler: nil)
        }
    }

    private func applyFocus(_ s: CameraSettings, _ d: AVCaptureDevice) {
        switch s.focusMode {
        case .auto:
            if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
        case .lock:
            if d.isFocusModeSupported(.locked) { d.focusMode = .locked }
        case .manual:
            if d.isLockingFocusWithCustomLensPositionSupported {
                d.setFocusModeLocked(lensPosition: min(max(s.lensPosition, 0), 1), completionHandler: nil)
            }
        }
    }

    private func applyWhiteBalance(_ s: CameraSettings, _ d: AVCaptureDevice) {
        switch s.whiteBalanceMode {
        case .auto:
            if d.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) { d.whiteBalanceMode = .continuousAutoWhiteBalance }
        case .lock:
            if d.isWhiteBalanceModeSupported(.locked) {
                d.setWhiteBalanceModeLocked(with: AVCaptureDevice.currentWhiteBalanceGains, completionHandler: nil)
            }
        case .manual:
            guard d.isWhiteBalanceModeSupported(.locked) else { return }
            let tt = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: s.whiteBalanceKelvin,
                                                                          tint: s.whiteBalanceTint)
            var g = d.deviceWhiteBalanceGains(for: tt)
            let maxG = d.maxWhiteBalanceGain
            g.redGain = min(max(g.redGain, 1), maxG)
            g.greenGain = min(max(g.greenGain, 1), maxG)
            g.blueGain = min(max(g.blueGain, 1), maxG)
            d.setWhiteBalanceModeLocked(with: g, completionHandler: nil)
        }
    }

    private func applyTorch(_ s: CameraSettings, _ d: AVCaptureDevice) {
        guard d.hasTorch, d.isTorchAvailable else { return }
        if s.torch > 0.01 {
            try? d.setTorchModeOn(level: min(s.torch, AVCaptureDevice.maxAvailableTorchLevel))
        } else if d.torchMode != .off {
            d.torchMode = .off
        }
    }

    /// Reads live values for telemetry (cheap property reads).
    func readout() -> CameraReadout {
        guard let d = device else { return CameraReadout() }
        var r = CameraReadout()
        r.iso = d.iso
        let secs = d.exposureDuration.seconds
        r.shutterDenominator = secs > 0 ? Float(1 / secs) : 0
        let tt = d.temperatureAndTintValues(for: d.deviceWhiteBalanceGains)
        r.whiteBalanceKelvin = tt.temperature
        r.lensPosition = d.lensPosition
        r.zoomDisplay = d.videoZoomFactor / max(capabilities.displayZoomMultiplier, 0.01)
        r.activeMode = activeMode
        return r
    }

    // MARK: Notifications

    @objc private func sessionRuntimeError(_ note: Notification) {
        let err = note.userInfo?[AVCaptureSessionErrorKey] as? AVError
        Log.camera.error("Runtime error: \(err?.localizedDescription ?? "unknown", privacy: .public)")
        onRuntimeError?(err?.localizedDescription ?? "Camera error")
        if err?.code == .mediaServicesWereReset {
            sessionQueue.async { if !self.session.isRunning { self.session.startRunning() } }
        }
    }

    @objc private func sessionInterruptionEnded(_ note: Notification) {
        sessionQueue.async { if !self.session.isRunning { self.session.startRunning() } }
    }
}

// MARK: - Frame delivery

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let frame = CameraFrame(pixelBuffer: pixelBuffer,
                                presentationTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
                                hostTime: hostTimeSeconds())
        consumer?.camera(didOutput: frame)
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        var reason = "unknown"
        if let r = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_DroppedFrameReason, attachmentModeOut: nil) as? String {
            reason = r
        }
        consumer?.cameraDidDropFrame(reason: reason)
    }
}
