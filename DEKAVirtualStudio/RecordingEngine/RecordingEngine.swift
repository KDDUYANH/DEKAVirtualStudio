//
//  RecordingEngine.swift
//  Local ISO recording with AVAssetWriter.
//   • PROGRAM: the MASTER NV12 buffers (exactly what goes to air)
//   • CAMERA:  the untouched camera buffers (clean plate for re-grading / re-keying in post)
//  Both are appended zero-copy through AVAssetWriterInputPixelBufferAdaptor.
//

import AVFoundation
import Photos

enum RecordingMode: String, Codable, CaseIterable, Identifiable {
    case program = "PROGRAM", camera = "CAMERA"
    var id: String { rawValue }
}

struct RecordingStatus: Equatable {
    var isRecording = false
    var mode: RecordingMode = .program
    var duration: TimeInterval = 0
    var fileBytes: Int64 = 0
    var freeBytes: Int64 = 0
    var lastFile: URL?
    var warning: String?
    var droppedFrames: Int = 0
}

final class RecordingEngine: MasterFrameSink, AudioSampleSink {

    static let lowStorageWarnBytes: Int64 = 2_000_000_000
    static let lowStorageStopBytes: Int64 = 500_000_000

    private let queue = DispatchQueue(label: "deka.recording", qos: .userInitiated)
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var sessionStart: CMTime?
    private var lastVideoPTS: CMTime = .invalid
    private var mode: RecordingMode = .program
    private var url: URL?
    private var pendingAudioSettings: (channels: Int, rate: Double)?
    private var lastStorageCheck: Double = 0

    private let statusBox = Locked(RecordingStatus())
    var status: RecordingStatus { statusBox.get() }
    var onAutoStop: ((String) -> Void)?

    static var directory: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    // MARK: Control

    func start(mode: RecordingMode, size: CGSize, fps: Int, cameraRotated180: Bool, audioChannels: Int?,
               codec: AVVideoCodecType = .hevc) throws {
        let free = SystemMetrics.freeStorageBytes()
        guard free > Self.lowStorageStopBytes else {
            throw NSError(domain: "DEKA.Recording", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Not enough storage to record (\(SystemMetrics.formatBytes(free)) free)."])
        }
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmmss"
        let url = Self.directory.appendingPathComponent("DEKA_\(mode.rawValue)_\(f.string(from: Date())).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        // Local masters are recorded at high quality (the stream is bitrate-limited, the file needn't be).
        let pixels = Double(size.width * size.height)
        let bitrate = Int(pixels * Double(fps) * (codec == .hevc ? 0.12 : 0.2))
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoMaxKeyFrameIntervalKey: fps * 2
            ] as [String: Any],
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        ])
        video.expectsMediaDataInRealTime = true
        // CAMERA mode records sensor-native buffers; flag the orientation instead of re-rendering.
        if mode == .camera && cameraRotated180 { video.transform = CGAffineTransform(rotationAngle: .pi) }
        guard writer.canAdd(video) else { throw NSError(domain: "DEKA.Recording", code: 2) }
        writer.add(video)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: nil)

        queue.sync {
            self.writer = writer
            self.videoInput = video
            self.adaptor = adaptor
            self.audioInput = nil
            self.sessionStart = nil
            self.lastVideoPTS = .invalid
            self.mode = mode
            self.url = url
            self.pendingAudioSettings = nil
            if let ch = audioChannels { self.addAudioInputIfNeeded(channels: ch, rate: AudioEngine.targetSampleRate) }
        }
        statusBox.set(RecordingStatus(isRecording: true, mode: mode, duration: 0, fileBytes: 0,
                                      freeBytes: free, lastFile: nil, warning: nil))
        Log.record.info("Recording \(mode.rawValue, privacy: .public) → \(url.lastPathComponent, privacy: .public)")
    }

    /// Audio input must exist before startWriting(). It is added at start() from the audio
    /// engine's known format, or (if the mic started later) before the first video frame.
    private func addAudioInputIfNeeded(channels: Int, rate: Double) {
        guard let writer, audioInput == nil, writer.status == .unknown else { return }
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = channels > 1 ? kAudioChannelLayoutTag_Stereo : kAudioChannelLayoutTag_Mono
        let layoutData = Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: channels > 1 ? 192_000 : 128_000,
            AVChannelLayoutKey: layoutData
        ])
        audio.expectsMediaDataInRealTime = true
        if writer.canAdd(audio) { writer.add(audio); audioInput = audio }
    }

    func stop(saveToPhotos: Bool = false) async -> URL? {
        let result: (AVAssetWriter, URL)? = queue.sync {
            guard let writer = self.writer, let url = self.url else { return nil }
            self.writer = nil
            if writer.status == .writing {
                self.videoInput?.markAsFinished()
                self.audioInput?.markAsFinished()
                return (writer, url)
            }
            writer.cancelWriting()
            return nil
        }
        statusBox.mutate { $0.isRecording = false }
        guard let (writer, url) = result else { return nil }
        await writer.finishWriting()
        guard writer.status == .completed else {
            statusBox.mutate { $0.warning = writer.error?.localizedDescription ?? "Recording failed." }
            return nil
        }
        statusBox.mutate { $0.lastFile = url }
        if saveToPhotos { await Self.saveToPhotos(url) }
        return url
    }

    static func saveToPhotos(_ url: URL) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return }
        try? await PHPhotoLibrary.shared().performChanges {
            _ = PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }

    // MARK: Sinks

    func consume(master: MasterFrame) {
        queue.async { [weak self] in
            guard let self, let writer = self.writer, let input = self.videoInput, let adaptor = self.adaptor else { return }
            let pb = self.mode == .program ? master.pixelBuffer : master.sourceCamera
            let pts = master.presentationTime
            if writer.status == .unknown {
                if let a = self.pendingAudioSettings { self.addAudioInputIfNeeded(channels: a.channels, rate: a.rate) }
                guard writer.startWriting() else {
                    self.statusBox.mutate { $0.warning = writer.error?.localizedDescription }
                    return
                }
                writer.startSession(atSourceTime: pts)
                self.sessionStart = pts
            }
            guard writer.status == .writing else { return }
            guard CMTimeCompare(pts, self.lastVideoPTS) > 0 || !self.lastVideoPTS.isValid else { return }
            if input.isReadyForMoreMediaData, adaptor.append(pb, withPresentationTime: pts) {
                self.lastVideoPTS = pts
            } else {
                self.statusBox.mutate { $0.droppedFrames += 1 }
            }
            self.updateStatus(pts: pts)
        }
    }

    func consume(audio: AudioChunk) {
        queue.async { [weak self] in
            guard let self, let writer = self.writer else { return }
            if writer.status == .unknown {
                self.pendingAudioSettings = (audio.channels, audio.sampleRate)
                return
            }
            guard writer.status == .writing, let input = self.audioInput, let start = self.sessionStart,
                  CMTimeCompare(audio.presentationTime, start) >= 0, input.isReadyForMoreMediaData,
                  let sb = AudioSampleBufferFactory.makeSampleBuffer(audio) else { return }
            input.append(sb)
        }
    }

    private func updateStatus(pts: CMTime) {
        guard let start = sessionStart else { return }
        let now = hostTimeSeconds()
        var free = statusBox.get().freeBytes
        var bytes = statusBox.get().fileBytes
        if now - lastStorageCheck > 2 {
            lastStorageCheck = now
            free = SystemMetrics.freeStorageBytes()
            if let url, let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize { bytes = Int64(size) }
            if free < Self.lowStorageStopBytes {
                Log.record.error("Storage critically low — stopping recording")
                let cb = onAutoStop
                DispatchQueue.main.async { cb?("Storage almost full — recording stopped and saved.") }
            }
        }
        statusBox.mutate {
            $0.duration = CMTimeGetSeconds(CMTimeSubtract(pts, start))
            $0.freeBytes = free
            $0.fileBytes = bytes
            $0.warning = free < Self.lowStorageWarnBytes ? "Low storage: \(SystemMetrics.formatBytes(free)) free" : nil
        }
    }
}
