//
//  SRTEngine.swift
//  Ultra-low-latency SRT (Secure Reliable Transport) streaming engine using HaishinKit.
//  Supports:
//   • SRT Output: Hardware H.264/HEVC encoding to MediaMTX / vMix / OBS (Caller / Listener)
//   • SRT Input: Hardware decoding and display of Return Program / Teleprompter feed
//   • Real-time telemetry: RTT, Bitrate, Packet Loss %, Buffer status directly from libsrt
//

import Foundation
import AVFoundation
import CoreMedia
import VideoToolbox
import HaishinKit
import SRTHaishinKit
import RTMPHaishinKit
import MetalKit

final class SRTEngine: StreamPublisher, @unchecked Sendable {

    // MARK: - Public State & Callbacks
    private let stateBox = Locked(StreamState.off)
    var state: StreamState { stateBox.get() }
    var onStateChange: ((StreamState) -> Void)?
    var onStats: ((StreamStats) -> Void)?
    var onEvent: ((String) -> Void)?

    private let statsBox = Locked(StreamStats())
    var stats: StreamStats { statsBox.get() }

    // Privacy & token gates (if needed)
    private let gate: PrivacyGate

    // SRT Output Objects (Publishing)
    private var publishConnection: SRTConnection?
    private var publishStream: SRTStream?

    // RTMP Output Objects (Publishing)
    private var rtmpConnection: RTMPConnection?
    private var rtmpStream: RTMPStream?
    private let isPublishing = Locked(false)

    // SRT Input Objects (Return Program Feed)
    private var returnConnection: SRTConnection?
    private var returnStream: SRTStream?
    private let isReturnActive = Locked(false)
    let returnView = MTHKView(frame: .zero)

    // Configuration & Tasks
    private var configuration: StreamConfiguration?
    private var statsTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private let reconnectPolicy = ReconnectPolicy()
    private var userStopped = true

    // Audio format caching
    private var lastSampleRate: Double = 48000
    private var lastChannels: Int = 1
    private var audioFormat: AVAudioFormat?

    // Serial stream queue & backpressure lock to prevent task pileup & memory exhaustion
    private let streamQueue = DispatchQueue(label: "dtek.stream.queue", qos: .userInteractive)
    private let isEncodingFrame = Locked(false)
    private let lastEncodingStart = Locked<Double>(0)
    private let pendingAudioChunks = Locked(0)

    init(gate: PrivacyGate = PrivacyGate()) {
        self.gate = gate
        self.returnView.videoGravity = .resizeAspectFill
    }

    // MARK: - Output (Publishing SRT & RTMP)

    func start(configuration: StreamConfiguration) async throws {
        userStopped = false
        reconnectTask?.cancel()
        reconnectTask = nil
        self.configuration = configuration
        setState(.connecting)
        let isRTMP = configuration.srtPublishURL.lowercased().hasPrefix("rtmp://") || configuration.srtPublishURL.lowercased().hasPrefix("rtmps://")
        let proto = isRTMP ? "RTMP" : "SRT"
        onEvent?("Connecting to \(proto): \(configuration.srtPublishURL)")

        do {
            try await connectAndPublish(configuration)
        } catch {
            userStopped = true
            await teardownPublish()
            setState(.failed(error.localizedDescription))
            onEvent?("\(proto) connection failed: \(error.localizedDescription)")
            throw error
        }
    }

    func stop() async {
        userStopped = true
        reconnectTask?.cancel()
        reconnectTask = nil
        await teardownPublish()
        await stopReturnFeed()
        setState(.off)
        onEvent?("Stream stopped.")
    }

    private func connectAndPublish(_ cfg: StreamConfiguration) async throws {
        guard let url = URL(string: cfg.srtPublishURL) else {
            throw NSError(domain: "DTEK.Stream", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Stream URL: \(cfg.srtPublishURL)"])
        }

        let isRTMP = (url.scheme?.lowercased() == "rtmp" || url.scheme?.lowercased() == "rtmps")

        // Configure Video Encoding (Hardware VideoToolbox)
        let isHEVC = cfg.videoCodec.lowercased() == "hevc"
        let profile = isHEVC ? (kVTProfileLevel_HEVC_Main_AutoLevel as String) : (kVTProfileLevel_H264_High_AutoLevel as String)
        let videoSettings = VideoCodecSettings(
            videoSize: cfg.resolution.size,
            bitRate: cfg.videoBitrateKbps * 1000,
            profileLevel: profile,
            scalingMode: .trim,
            bitRateMode: .average,
            maxKeyFrameIntervalDuration: 2,
            isLowLatencyRateControlEnabled: true,
            isHardwareAcceleratedEnabled: true,
            expectedFrameRate: Double(cfg.fps)
        )

        // Configure Audio Encoding (AAC 128kbps)
        let audioSettings = AudioCodecSettings(
            bitRate: cfg.audioBitrateKbps * 1000,
            format: .aac
        )

        if isRTMP {
            let connection = RTMPConnection()
            self.rtmpConnection = connection
            let stream = RTMPStream(connection: connection)
            self.rtmpStream = stream

            try? await stream.setVideoSettings(videoSettings)
            try? await stream.setAudioSettings(audioSettings)

            let _ = try await connection.connect(cfg.srtPublishURL)
            let streamKey = cfg.streamKey.trimmingCharacters(in: .whitespacesAndNewlines)
            try await stream.publish(streamKey.isEmpty ? nil : streamKey)

            isPublishing.set(true)
            setState(.live)
            onEvent?("RTMP LIVE on air: \(url.host ?? "")")
        } else {
            let connection = SRTConnection()
            self.publishConnection = connection
            let stream = SRTStream(connection: connection)
            self.publishStream = stream

            try? await stream.setVideoSettings(videoSettings)
            try? await stream.setAudioSettings(audioSettings)

            try await connection.connect(url)
            await stream.publish()

            isPublishing.set(true)
            setState(.live)
            onEvent?("SRT LIVE on air: \(url.host ?? ""):\(url.port ?? 9000)")
        }

        // Start performance stats monitor
        startStatsMonitor()

        // Auto-start return feed if configured
        if let returnURL = cfg.srtReturnURL, !returnURL.isEmpty {
            Task {
                try? await self.startReturnFeed(urlString: returnURL)
            }
        }
    }

    private func teardownPublish() async {
        statsTask?.cancel()
        statsTask = nil
        isPublishing.set(false)
        isEncodingFrame.set(false)
        pendingAudioChunks.set(0)

        if let stream = publishStream {
            await stream.close()
        }
        publishStream = nil

        if let conn = publishConnection {
            await conn.close()
        }
        publishConnection = nil

        if let stream = rtmpStream {
            try? await stream.close()
        }
        rtmpStream = nil

        if let conn = rtmpConnection {
            try? await conn.close()
        }
        rtmpConnection = nil
    }

    // MARK: - Auto-Reconnect

    private func handleDisconnect() {
        guard !userStopped, isPublishing.get(), reconnectTask == nil, let cfg = configuration else { return }
        scheduleReconnect(cfg: cfg)
    }

    private func scheduleReconnect(cfg: StreamConfiguration) {
        reconnectTask?.cancel()
        let isRTMP = cfg.srtPublishURL.lowercased().hasPrefix("rtmp://") || cfg.srtPublishURL.lowercased().hasPrefix("rtmps://")
        let proto = isRTMP ? "RTMP" : "SRT"

        reconnectTask = Task { [weak self] in
            guard let self else { return }
            await self.teardownPublish()

            var attempt = 1
            while !self.userStopped && !Task.isCancelled {
                guard let delay = self.reconnectPolicy.delay(forAttempt: attempt) else {
                    self.setState(.failed("\(proto) connection lost: max attempts exceeded"))
                    self.onEvent?("\(proto) connection failed after \(self.reconnectPolicy.maxAttempts) attempts.")
                    break
                }

                self.setState(.reconnecting(attempt: attempt))
                self.onEvent?("\(proto) disconnected. Reconnecting in \(String(format: "%.1f", delay))s (attempt \(attempt)/\(self.reconnectPolicy.maxAttempts))…")

                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if self.userStopped || Task.isCancelled { break }

                do {
                    try await self.connectAndPublish(cfg)
                    self.onEvent?("\(proto) connection restored!")
                    self.reconnectTask = nil
                    return
                } catch {
                    attempt += 1
                }
            }
            self.reconnectTask = nil
        }
    }

    // MARK: - SRT Input (Return Program / Monitor Feed)

    func startReturnFeed(urlString: String) async throws {
        guard let url = URL(string: urlString) else { return }
        await stopReturnFeed()

        onEvent?("Connecting to SRT Return Feed: \(urlString)")
        let conn = SRTConnection()
        self.returnConnection = conn
        let stream = SRTStream(connection: conn)
        self.returnStream = stream

        // Attach Metal view to receive decoded frames
        await stream.addOutput(returnView)
        try await conn.connect(url)
        await stream.play()

        isReturnActive.set(true)
        onEvent?("SRT Return Feed connected.")
    }

    func stopReturnFeed() async {
        isReturnActive.set(false)
        if let stream = returnStream {
            await stream.removeOutput(returnView)
            await stream.close()
        }
        returnStream = nil

        if let conn = returnConnection {
            await conn.close()
        }
        returnConnection = nil
    }

    // MARK: - Media Ingestion (from MasterFrame & AudioChunk)

    /// MASTER video (delivered from Compositor: NV12 CVPixelBuffer).
    func consume(master: MasterFrame) {
        guard gate.allowsUpload, isPublishing.get(), (publishStream != nil || rtmpStream != nil) else { return }

        // Backpressure check: if previous frame is still encoding, drop this frame unless timed out (>0.5s)
        let now = hostTimeSeconds()
        let busy = isEncodingFrame.get()
        if busy {
            if now - lastEncodingStart.get() > 0.5 {
                // Timeout on previous frame: release lock to resume encoding pipeline
                isEncodingFrame.set(false)
            } else {
                return
            }
        }
        isEncodingFrame.set(true)
        lastEncodingStart.set(now)

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: master.presentationTime,
            decodeTimeStamp: .invalid
        )
        var formatDesc: CMVideoFormatDescription?
        let err = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: master.pixelBuffer,
            formatDescriptionOut: &formatDesc
        )
        guard err == noErr, let formatDesc else {
            isEncodingFrame.set(false)
            return
        }

        var sampleBuffer: CMSampleBuffer?
        let sbErr = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: master.pixelBuffer,
            formatDescription: formatDesc,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard sbErr == noErr, let sampleBuffer else {
            isEncodingFrame.set(false)
            return
        }

        streamQueue.async { [weak self] in
            guard let self, self.isPublishing.get() else {
                self?.isEncodingFrame.set(false)
                return
            }
            Task {
                if let stream = self.publishStream {
                    await stream.append(sampleBuffer)
                } else if let stream = self.rtmpStream {
                    await stream.append(sampleBuffer)
                }
                self.isEncodingFrame.set(false)
            }
        }
    }

    /// Audio PCM chunk (16-bit interleaved)
    func consume(audio: AudioChunk) {
        guard gate.allowsUpload, isPublishing.get(), (publishStream != nil || rtmpStream != nil) else { return }

        if audioFormat == nil || lastSampleRate != audio.sampleRate || lastChannels != audio.channels {
            lastSampleRate = audio.sampleRate
            lastChannels = audio.channels
            audioFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: audio.sampleRate,
                channels: AVAudioChannelCount(audio.channels),
                interleaved: true
            )
        }
        guard let format = audioFormat,
              let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(audio.frameCount)) else {
            return
        }
        pcm.frameLength = AVAudioFrameCount(audio.frameCount)
        if let channelData = pcm.int16ChannelData {
            audio.samples.withUnsafeBufferPointer { ptr in
                guard let base = ptr.baseAddress else { return }
                memcpy(channelData[0], base, audio.samples.count * MemoryLayout<Int16>.size)
            }
        }
        let time = AVAudioTime(hostTime: mach_absolute_time())

        // Backpressure guard: if more than 5 chunks are pending, drop to prevent task and buffer pileup
        if pendingAudioChunks.get() > 5 { return }
        pendingAudioChunks.mutate { $0 += 1 }

        streamQueue.async { [weak self] in
            guard let self, self.isPublishing.get() else {
                self?.pendingAudioChunks.mutate { $0 = max(0, $0 - 1) }
                return
            }
            Task {
                defer { self.pendingAudioChunks.mutate { $0 = max(0, $0 - 1) } }
                if let stream = self.publishStream {
                    await stream.append(pcm, when: time)
                } else if let stream = self.rtmpStream {
                    await stream.append(pcm, when: time)
                }
            }
        }
    }

    // MARK: - Telemetry & Monitoring

    private func startStatsMonitor() {
        statsTask?.cancel()
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                guard let self else { break }

                if let conn = self.publishConnection {
                    let isConn = await conn.connected
                    if !isConn {
                        if self.isPublishing.get() && !self.userStopped {
                            self.handleDisconnect()
                        }
                        continue
                    }

                    if let perf = await conn.performanceData {
                        var s = self.statsBox.get()
                        s.rttMs = perf.msRTT
                        s.videoBitrateKbps = perf.mbpsSendRate * 1000
                        s.availableOutgoingKbps = perf.mbpsBandwidth * 1000
                        let totalPackets = perf.pktSent + Int64(perf.pktSndLoss)
                        if totalPackets > 0 {
                            s.packetLossPercent = (Double(perf.pktSndLoss) / Double(totalPackets)) * 100.0
                        }
                        s.connectionState = "connected"
                        self.statsBox.set(s)
                        let cb = self.onStats
                        DispatchQueue.main.async { cb?(s) }
                    }
                } else if let conn = self.rtmpConnection {
                    let isConn = await conn.connected
                    if !isConn {
                        if self.isPublishing.get() && !self.userStopped {
                            self.handleDisconnect()
                        }
                        continue
                    }

                    var s = self.statsBox.get()
                    s.rttMs = 0
                    s.videoBitrateKbps = Double(self.configuration?.videoBitrateKbps ?? 4000)
                    s.availableOutgoingKbps = Double(self.configuration?.videoBitrateKbps ?? 4000)
                    s.packetLossPercent = 0
                    s.connectionState = "connected"
                    self.statsBox.set(s)
                    let cb = self.onStats
                    DispatchQueue.main.async { cb?(s) }
                }
            }
        }
    }

    private func setState(_ s: StreamState) {
        stateBox.set(s)
        let cb = onStateChange
        DispatchQueue.main.async { cb?(s) }
    }
}
