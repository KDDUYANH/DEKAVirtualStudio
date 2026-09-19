//
//  MillicastEngine.swift
//  Dolby OptiView Real-time Streaming (Millicast) publisher, built on the OFFICIAL
//  MillicastSDK Swift package (v2.6.0, which embeds Google WebRTC). We do not ship a second
//  WebRTC copy — two WebRTC builds in one binary collide at link time.
//
//  MASTER NV12 CVPixelBuffer ──MCCoreVideoSource.onPixelBuffer(_:withTimestamp:)──► VideoToolbox H.264
//  AudioChunk (Int16, 10 ms) ──MCCustomAudioSource.onAudioFrame(_:)───────────────► Opus
//  RTCPeerConnection (inside the SDK) ──► Millicast director/publish ──► viewers
//

import Foundation
import CoreMedia
import MillicastSDK

final class MillicastEngine: StreamPublisher {

    // Public state (read on main)
    private let stateBox = Locked(StreamState.off)
    var state: StreamState { stateBox.get() }
    var onStateChange: ((StreamState) -> Void)?
    var onStats: ((StreamStats) -> Void)?
    var onEvent: ((String) -> Void)?

    // Dependencies
    private let gate: PrivacyGate
    private let tokens: TokenService

    // SDK objects
    private var publisher: MCPublisher?
    private var videoSource: MCCoreVideoSource?
    private var audioSource: MCCustomAudioSource?
    private var videoTrack: MCVideoTrack?
    private var audioTrack: MCAudioTrack?

    // Session
    private var configuration: StreamConfiguration?
    private var credentials: PublishCredentials?
    private var observers: [Task<Void, Never>] = []
    private var reconnectTask: Task<Void, Never>?
    private let publishing = Locked(false)        // frames are forwarded only while true
    private let reconnectPolicy = ReconnectPolicy()
    private var userStopped = true

    // Stats
    private var lastSample: OutboundSample?
    private let statsBox = Locked(StreamStats())
    var stats: StreamStats { statsBox.get() }

    // Audio re-chunking to exact 10 ms frames (WebRTC's native unit)
    private let audioQueue = DispatchQueue(label: "deka.millicast.audio", qos: .userInteractive)
    private var pending: [Int16] = []
    private var pendingChannels = 1
    private var pendingRate = 48_000.0

    init(gate: PrivacyGate, tokens: TokenService) {
        self.gate = gate
        self.tokens = tokens
    }

    static var sdkSupportedVideoCodecs: [String] { MCMedia.getSupportedVideoCodecs() }
    static var sdkSupportedAudioCodecs: [String] { MCMedia.getSupportedAudioCodecs() }

    // MARK: Start / stop

    func start(configuration: StreamConfiguration) async throws {
        userStopped = false
        self.configuration = configuration
        do {
            try await connectAndPublish(configuration)
        } catch {
            userStopped = true
            await teardown()
            setState(.failed(error.localizedDescription))
            throw error
        }
    }

    func stop() async {
        userStopped = true
        reconnectTask?.cancel()
        reconnectTask = nil
        publishing.set(false)
        if let publisher {
            try? await publisher.unpublish()
            try? await publisher.disconnect()
        }
        await teardown()
        if let creds = credentials { await tokens.revoke(creds) }
        credentials = nil
        setState(.off)
    }

    private func connectAndPublish(_ cfg: StreamConfiguration) async throws {
        setState(.authorizing)
        let creds = try await tokens.publishCredentials(streamName: cfg.streamName)
        credentials = creds
        if creds.isDeveloperToken { onEvent?("Using DEVELOPER token from Keychain (no backend).") }

        setState(.connecting)
        let publisher = MCPublisher()
        self.publisher = publisher
        observe(publisher)

        let vSource = MCCoreVideoSourceBuilder().build()
        let aSource = MCCustomAudioSourceBuilder().build()
        guard let vTrack = vSource.startCapture() as? MCVideoTrack,
              let aTrack = aSource.startCapture() as? MCAudioTrack else {
            throw NSError(domain: "DEKA.Millicast", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create WebRTC tracks."])
        }
        videoSource = vSource; audioSource = aSource
        videoTrack = vTrack; audioTrack = aTrack
        await publisher.addTrack(with: vTrack)
        await publisher.addTrack(with: aTrack)

        let c = MCPublisherCredentials()
        c.streamName = creds.streamName
        c.token = creds.token
        c.apiUrl = creds.apiURL
        try await publisher.setCredentials(c)

        let connectOptions = MCConnectionOptions()
        connectOptions.autoReconnect = true          // SDK-level ICE / websocket recovery
        try await publisher.connect(with: connectOptions)

        let options = MCClientOptions()
        options.videoCodec = cfg.videoCodec           // "h264" → VideoToolbox hardware encoder
        options.audioCodec = "opus"
        options.stereo = pendingChannels > 1
        options.statsDelayMs = 1000
        options.degradationPreferences = cfg.fps >= 50 ? .maintainFrameRate : .balanced
        let bitrate = MCBitrateSettings()
        bitrate.maxBitrateKbps = cfg.videoBitrateKbps
        bitrate.minBitrateKbps = cfg.minVideoBitrateKbps
        bitrate.startBitrateKbps = min(cfg.videoBitrateKbps, max(cfg.minVideoBitrateKbps, cfg.videoBitrateKbps * 3 / 4))
        bitrate.disableBWE = false
        options.bitrateSettings = bitrate
        try await publisher.publish(with: options)
        await publisher.enableStats(true)

        lastSample = nil
        publishing.set(true)
        setState(.live)
        Log.stream.notice("Publishing \(creds.streamName, privacy: .public) \(cfg.resolution.rawValue, privacy: .public)\(cfg.fps)")
    }

    private func teardown() async {
        observers.forEach { $0.cancel() }
        observers.removeAll()
        publishing.set(false)
        audioSource?.stopCapture()
        videoSource?.stopCapture()
        if let p = publisher { await p.clearTracks() }
        publisher = nil
        videoSource = nil; audioSource = nil
        videoTrack = nil; audioTrack = nil
        audioQueue.sync { pending.removeAll() }
    }

    // MARK: Reconnect (fresh token each attempt: an expired token must not end the show)

    private func scheduleReconnect(reason: String) {
        guard !userStopped, reconnectTask == nil, let cfg = configuration else { return }
        publishing.set(false)
        onEvent?("Connection lost: \(reason). Reconnecting…")
        reconnectTask = Task { [weak self] in
            guard let self else { return }
            var attempt = 1
            while !Task.isCancelled, !self.userStopped {
                guard let delay = self.reconnectPolicy.delay(forAttempt: attempt) else {
                    self.setState(.failed("Could not reconnect after \(attempt - 1) attempts."))
                    break
                }
                self.setState(.reconnecting(attempt: attempt))
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if Task.isCancelled || self.userStopped { break }
                await self.teardown()
                do {
                    try await self.connectAndPublish(cfg)
                    self.onEvent?("Reconnected after \(attempt) attempt(s).")
                    break
                } catch {
                    Log.stream.error("Reconnect \(attempt) failed: \(error.localizedDescription, privacy: .public)")
                    attempt += 1
                }
            }
            self.reconnectTask = nil
        }
    }

    // MARK: SDK event streams

    private func observe(_ p: MCPublisher) {
        observers.append(Task { [weak self] in
            for await s in p.peerConnectionState() {
                guard let self else { return }
                self.statsBox.mutate { $0.connectionState = Self.describe(s) }
                switch s {
                case .failed: self.scheduleReconnect(reason: "peer connection failed")
                case .reconnecting: if self.state == .live { self.setState(.reconnecting(attempt: 0)) }
                case .connected: if case .reconnecting = self.state, self.reconnectTask == nil { self.setState(.live) }
                default: break
                }
            }
        })
        observers.append(Task { [weak self] in
            for await e in p.httpError() {
                self?.onEvent?("HTTP \(e.code): \(e.reason)")
            }
        })
        observers.append(Task { [weak self] in
            for await e in p.signalingError() {
                self?.onEvent?("Signaling: \(e.reason)")
            }
        })
        observers.append(Task { [weak self] in
            for await n in p.viewerCount() {
                self?.statsBox.mutate { $0.viewers = Int(n) }
            }
        })
        observers.append(Task { [weak self] in
            for await report in p.statsReport() {
                self?.ingest(report)
            }
        })
    }

    private static func describe(_ s: MCConnectionState) -> String {
        switch s {
        case .idle: return "idle"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .reconnecting: return "reconnecting"
        case .disconnecting: return "disconnecting"
        case .failed: return "failed"
        @unknown default: return "unknown"
        }
    }

    // MARK: Stats (real WebRTC counters)

    private func ingest(_ report: MCStatsReport) {
        var videoBytes: UInt64 = 0, audioBytes: UInt64 = 0, framesEncoded: UInt64 = 0
        var ts: Double = 0
        var s = statsBox.get()

        for case let o as MCOutboundRtpStreamStats in report.getStatsOf(MCOutboundRtpStreamStats.get_type()) ?? [] {
            ts = max(ts, Double(o.timestamp))
            if o.kind == "video" {
                videoBytes += o.bytes_sent
                framesEncoded += UInt64(o.frames_encoded)
                s.targetBitrateKbps = o.target_bitrate / 1000
                s.framesPerSecond = o.frames_per_second
                s.frameWidth = Int(o.frame_width)
                s.frameHeight = Int(o.frame_height)
                s.framesSent = Int(o.frames_sent)
                s.framesEncoded = Int(o.frames_encoded)
                s.qualityLimitation = o.quality_limitation_reason ?? "none"
                s.encoder = o.encoder_implementation ?? ""
            } else if o.kind == "audio" {
                audioBytes += o.bytes_sent
            }
        }
        for case let r as MCRemoteInboundRtpStreamStats in report.getStatsOf(MCRemoteInboundRtpStreamStats.get_type()) ?? [] {
            if r.kind == "video" {
                s.rttMs = r.round_trip_time * 1000
                s.packetLossPercent = r.fraction_lost * 100
                s.jitterMs = r.jitter * 1000
            }
        }
        for case let pair as MCIceCandidatePairStats in report.getStatsOf(MCIceCandidatePairStats.get_type()) ?? [] {
            if pair.current_round_trip_time > 0, s.rttMs == 0 { s.rttMs = pair.current_round_trip_time * 1000 }
            if pair.available_outgoing_bitrate > 0 { s.availableOutgoingKbps = pair.available_outgoing_bitrate / 1000 }
        }

        let sample = OutboundSample(timestampMs: ts, videoBytesSent: videoBytes, audioBytesSent: audioBytes, framesEncoded: framesEncoded)
        if let prev = lastSample {
            s.videoBitrateKbps = StatsMath.kbps(bytesNow: sample.videoBytesSent, bytesBefore: prev.videoBytesSent,
                                                msNow: sample.timestampMs, msBefore: prev.timestampMs)
            s.audioBitrateKbps = StatsMath.kbps(bytesNow: sample.audioBytesSent, bytesBefore: prev.audioBytesSent,
                                                msNow: sample.timestampMs, msBefore: prev.timestampMs)
        }
        lastSample = sample
        statsBox.set(s)
        onStats?(s)
    }

    // MARK: Media input

    private func setState(_ s: StreamState) {
        stateBox.set(s)
        let cb = onStateChange
        DispatchQueue.main.async { cb?(s) }
    }

    /// MASTER video (delivery queue). Only the processed program — never the raw camera.
    func consume(master: MasterFrame) {
        guard gate.allowsUpload, publishing.get(), let source = videoSource else { return }
        source.onPixelBuffer(master.pixelBuffer, withTimestamp: master.presentationTime)
    }

    /// Program audio (audio tap thread) → exact 10 ms frames.
    func consume(audio: AudioChunk) {
        guard gate.allowsUpload, publishing.get() else { return }
        audioQueue.async { [weak self] in
            guard let self, let source = self.audioSource else { return }
            if self.pendingChannels != audio.channels || self.pendingRate != audio.sampleRate {
                self.pending.removeAll()
                self.pendingChannels = audio.channels
                self.pendingRate = audio.sampleRate
            }
            self.pending.append(contentsOf: audio.samples)
            let framesPer10ms = Int(audio.sampleRate / 100)
            let chunk = framesPer10ms * audio.channels
            while self.pending.count >= chunk {
                self.pending.withUnsafeBufferPointer { buf in
                    let frame = MCAudioFrame()
                    frame.bitsPerSample = 16
                    frame.sampleRate = Int32(audio.sampleRate)
                    frame.channelNumber = audio.channels
                    frame.frameNumber = framesPer10ms
                    frame.data = UnsafeRawPointer(buf.baseAddress!)
                    source.onAudioFrame(frame)       // the SDK copies the samples synchronously
                }
                self.pending.removeFirst(chunk)
            }
        }
    }
}
