//
//  AudioEngine.swift
//  AVAudioSession + AVAudioEngine program audio chain:
//
//    Mic (built-in / wired / USB / Bluetooth HFP)
//      → Gain (AVAudioUnitEQ global gain, −24…+24 dB, −96 dB = mute)
//      → Compressor (AUDynamicsProcessor)
//      → Limiter (AUPeakLimiter) → Ceiling trim
//      → tap: meters (vDSP) + Int16 48 kHz chunks → stream / recorder
//
//  The engine's speaker output is silenced (no monitoring feedback through the phone speaker).
//

import AVFoundation
import Accelerate
import AudioToolbox

struct AudioLevels: Equatable {
    var peakDB: [Float] = [-120, -120]    // L, R (mono inputs are mirrored to both meters)
    var rmsDB: [Float] = [-120, -120]
    var clipCount: Int = 0                // samples that reached full scale since start
    var gainReductionDB: Float = 0
}

struct AudioInputOption: Identifiable, Equatable {
    let id: String          // port UID
    let name: String
    let kind: String        // Built-in, Wired, USB, Bluetooth
}

final class AudioEngine {

    enum AudioError: LocalizedError {
        case notAuthorized, noInput
        var errorDescription: String? {
            switch self {
            case .notAuthorized: return "Microphone access is not allowed. Enable it in Settings."
            case .noInput: return "No microphone input is available."
            }
        }
    }

    private let engine = AVAudioEngine()
    private let gain = AVAudioUnitEQ(numberOfBands: 0)
    private let compressor = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_DynamicsProcessor,
        componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
    private let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect, componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
    private let ceiling = AVAudioMixerNode()

    private let sinks = Locked<[ObjectIdentifier: AudioSampleSink]>([:])
    private let levelsBox = Locked(AudioLevels())
    private let settingsBox = Locked(AudioSettings())
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    private let queue = DispatchQueue(label: "deka.audio.control", qos: .userInitiated)
    private(set) var isRunning = false

    var levels: AudioLevels { levelsBox.get() }
    /// Channel count of the program audio delivered to sinks (nil until the engine runs).
    var outputChannels: Int? { outputFormat.map { Int($0.channelCount) } }
    var onRouteChanged: (() -> Void)?

    static let targetSampleRate: Double = 48_000

    init() {
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(routeChanged(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        nc.addObserver(self, selector: #selector(interruption(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        nc.addObserver(self, selector: #selector(configurationChanged(_:)), name: .AVAudioEngineConfigurationChange, object: engine)
    }

    static func requestAccess() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    // MARK: Session

    func configureSession() throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playAndRecord, mode: .videoRecording,
                          options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker])
        try s.setPreferredSampleRate(Self.targetSampleRate)
        try s.setPreferredIOBufferDuration(0.01)   // 10 ms: WebRTC's native frame size
        try s.setActive(true, options: [])
        if let uid = settingsBox.get().preferredInputUID { try? selectInput(uid: uid) }
    }

    var availableInputs: [AudioInputOption] {
        (AVAudioSession.sharedInstance().availableInputs ?? []).map { port in
            let kind: String
            switch port.portType {
            case .builtInMic: kind = "Built-in"
            case .headsetMic: kind = "Wired"
            case .usbAudio: kind = "USB"
            case .bluetoothHFP: kind = "Bluetooth"
            case .lineIn: kind = "Line In"
            default: kind = port.portType.rawValue
            }
            return AudioInputOption(id: port.uid, name: port.portName, kind: kind)
        }
    }

    var currentInputName: String {
        AVAudioSession.sharedInstance().currentRoute.inputs.first?.portName ?? "—"
    }

    func selectInput(uid: String) throws {
        let s = AVAudioSession.sharedInstance()
        guard let port = s.availableInputs?.first(where: { $0.uid == uid }) else { return }
        try s.setPreferredInput(port)
        settingsBox.mutate { $0.preferredInputUID = uid }
    }

    // MARK: Engine

    func start() throws {
        guard !isRunning else { return }
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.channelCount > 0, inFormat.sampleRate > 0 else { throw AudioError.noInput }

        engine.attach(gain)
        engine.attach(compressor)
        engine.attach(limiter)
        engine.attach(ceiling)
        engine.connect(input, to: gain, format: inFormat)
        engine.connect(gain, to: compressor, format: inFormat)
        engine.connect(compressor, to: limiter, format: inFormat)
        engine.connect(limiter, to: ceiling, format: inFormat)
        engine.connect(ceiling, to: engine.mainMixerNode, format: inFormat)
        engine.mainMixerNode.outputVolume = 0   // no speaker monitoring

        let channels = min(inFormat.channelCount, 2)
        guard let outFmt = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Self.targetSampleRate,
                                         channels: channels, interleaved: true) else { throw AudioError.noInput }
        outputFormat = outFmt
        converter = AVAudioConverter(from: ceiling.outputFormat(forBus: 0), to: outFmt)

        ceiling.installTap(onBus: 0, bufferSize: 480, format: nil) { [weak self] buffer, time in
            self?.process(buffer: buffer, time: time)
        }
        applyEffects(settingsBox.get())
        engine.prepare()
        try engine.start()
        isRunning = true
        Log.audio.info("Audio engine started: \(inFormat.sampleRate) Hz, \(inFormat.channelCount) ch")
    }

    func stop() {
        guard isRunning else { return }
        ceiling.removeTap(onBus: 0)
        engine.stop()
        engine.detach(gain); engine.detach(compressor); engine.detach(limiter); engine.detach(ceiling)
        isRunning = false
    }

    func apply(_ settings: AudioSettings) {
        settingsBox.set(settings)
        applyEffects(settings)
    }

    private func applyEffects(_ s: AudioSettings) {
        gain.globalGain = s.muted ? -96 : max(-24, min(24, s.gainDB))

        let c = compressor.audioUnit
        compressor.bypass = !s.compressorEnabled
        AudioUnitSetParameter(c, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, s.compressorThresholdDB, 0)
        // HeadRoom sets the effective ratio: smaller headroom = harder compression.
        let headroom = max(0.5, min(40, 20 / max(s.compressorRatio, 1)))
        AudioUnitSetParameter(c, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, headroom, 0)
        AudioUnitSetParameter(c, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, 0.005, 0)
        AudioUnitSetParameter(c, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, 0.12, 0)

        let l = limiter.audioUnit
        limiter.bypass = !s.limiterEnabled
        AudioUnitSetParameter(l, kLimiterParam_AttackTime, kAudioUnitScope_Global, 0, 0.002, 0)
        AudioUnitSetParameter(l, kLimiterParam_DecayTime, kAudioUnitScope_Global, 0, 0.06, 0)
        AudioUnitSetParameter(l, kLimiterParam_PreGain, kAudioUnitScope_Global, 0, 0, 0)
        // AUPeakLimiter holds peaks at full scale; the trim after it sets the true ceiling (e.g. −1 dBFS).
        ceiling.outputVolume = s.limiterEnabled ? powf(10, min(0, s.limiterCeilingDB) / 20) : 1
    }

    // MARK: Sinks

    func addSink(_ sink: AudioSampleSink) { sinks.mutate { $0[ObjectIdentifier(sink)] = sink } }
    func removeSink(_ sink: AudioSampleSink) { sinks.mutate { $0[ObjectIdentifier(sink)] = nil } }

    // MARK: Tap (real-time audio thread → keep it light)

    private func process(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        meter(buffer)
        let targets = Array(sinks.get().values)
        guard !targets.isEmpty, let converter, let outputFormat else { return }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
        guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
        var fed = false
        var error: NSError?
        _ = converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, out.frameLength > 0, let data = out.int16ChannelData else { return }

        let channels = Int(outputFormat.channelCount)
        let frames = Int(out.frameLength)
        let samples = Array(UnsafeBufferPointer(start: data[0], count: frames * channels))
        let seconds = time.isHostTimeValid ? AVAudioTime.seconds(forHostTime: time.hostTime) : hostTimeSeconds()
        let chunk = AudioChunk(samples: samples, channels: channels, sampleRate: outputFormat.sampleRate,
                               frameCount: frames, presentationTime: CMTime(seconds: seconds, preferredTimescale: 48_000))
        targets.forEach { $0.consume(audio: chunk) }
    }

    private func meter(_ buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData else { return }
        let n = vDSP_Length(buffer.frameLength)
        guard n > 0 else { return }
        let count = Int(buffer.format.channelCount)
        var peaks: [Float] = []
        var rmss: [Float] = []
        var clips = 0
        for i in 0..<min(count, 2) {
            var peak: Float = 0
            var rms: Float = 0
            vDSP_maxmgv(ch[i], 1, &peak, n)
            vDSP_rmsqv(ch[i], 1, &rms, n)
            if peak >= 0.999 { clips += 1 }
            peaks.append(Self.dB(peak))
            rmss.append(Self.dB(rms))
        }
        if peaks.count == 1 { peaks.append(peaks[0]); rmss.append(rmss[0]) }
        var gr: Float = 0
        AudioUnitGetParameter(compressor.audioUnit, kDynamicsProcessorParam_CompressionAmount, kAudioUnitScope_Global, 0, &gr)
        levelsBox.mutate { l in
            // Peak hold with ~20 dB/s fall so the meter is readable at a glance.
            for i in 0..<2 {
                l.peakDB[i] = max(peaks[i], l.peakDB[i] - 0.2)
                l.rmsDB[i] = rmss[i]
            }
            l.clipCount += clips
            l.gainReductionDB = gr
        }
    }

    static func dB(_ linear: Float) -> Float { linear > 0 ? max(-120, 20 * log10f(linear)) : -120 }

    // MARK: Notifications

    @objc private func routeChanged(_ note: Notification) {
        Log.audio.info("Audio route changed → \(self.currentInputName, privacy: .public)")
        onRouteChanged?()
    }

    @objc private func interruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .ended {
            queue.async { [weak self] in self?.restart() }
        }
    }

    @objc private func configurationChanged(_ note: Notification) {
        // Input format changed (e.g. a USB interface was plugged in): rebuild the graph.
        queue.async { [weak self] in self?.restart() }
    }

    private func restart() {
        let wasRunning = isRunning
        stop()
        guard wasRunning else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try start()
        } catch {
            Log.audio.error("Audio restart failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
