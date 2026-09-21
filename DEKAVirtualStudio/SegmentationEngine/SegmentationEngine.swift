//
//  SegmentationEngine.swift
//  Runs person segmentation ASYNCHRONOUSLY. The capture/render thread never waits for AI:
//  it always composites with the most recent mask. When inference can't keep up the engine
//  (1) lowers the inference rate, (2) reuses the previous mask, (3) lowers model quality,
//  and (4) finally asks the controller to fall back to chroma — in that order.
//

import Foundation
import CoreVideo
import Metal

/// A mask texture plus whatever must stay alive until the GPU has finished reading it
/// (the CVMetalTexture wrapping Vision's IOSurface).
struct MaskTexture {
    let texture: MTLTexture
    let keepAlive: AnyObject?
}

struct SegmentationStats: Equatable {
    var backend = "—"
    var inferenceMs: Double = 0
    var effectiveFPS: Double = 0
    var quality: SegmentationQuality = .balanced
    var targetFPS: Int = 30
    var framesReused: Int = 0
    var lastError: String?
}

final class SegmentationEngine {

    private let queue = DispatchQueue(label: "dtek.ai.segmentation", qos: .userInitiated)
    private let context: MetalContext
    private var segmenter: PersonSegmenter
    private let inFlight = Locked(false)
    private let latestMask = Locked<MaskTexture?>(nil)
    private let config = Locked((quality: SegmentationQuality.balanced, targetFPS: 30, enabled: false))
    private var lastSubmitTime: Double = 0
    private var ewmaMs: Double = 0
    private var completions: [Double] = []
    private let statsBox = Locked(SegmentationStats())
    private var uploadTextures: [MTLTexture] = []   // ping-pong fallback when the mask isn't IOSurface-backed
    private var uploadIndex = 0

    /// Called (on the AI queue) when even the fastest setting cannot keep up.
    var onFallbackSuggested: (() -> Void)?

    init(context: MetalContext) {
        self.context = context
        if let coreML = try? CoreMLPersonSegmenter() {
            segmenter = coreML
        } else {
            segmenter = VisionPersonSegmenter(quality: .balanced)
        }
        statsBox.mutate { $0.backend = segmenter.name }
    }

    var stats: SegmentationStats { statsBox.get() }

    func configure(enabled: Bool, settings: SegmentationSettings) {
        config.set((settings.quality, max(5, min(settings.targetFPS, 60)), enabled))
        queue.async { self.segmenter.setQuality(settings.quality) }
        if !enabled { latestMask.set(nil) }
        statsBox.mutate { $0.quality = settings.quality; $0.targetFPS = settings.targetFPS }
    }

    /// Latest available mask (may be from a previous frame). nil until the first result.
    func currentMask() -> MaskTexture? { latestMask.get() }

    /// Called on the capture thread for every frame. Non-blocking.
    func submit(_ frame: CameraFrame) {
        let cfg = config.get()
        guard cfg.enabled else { return }
        let interval = 1.0 / Double(cfg.targetFPS)
        guard frame.hostTime - lastSubmitTime >= interval * 0.9 else {
            statsBox.mutate { $0.framesReused += 1 }
            return
        }
        // Drop, don't queue: if the previous inference is still running we reuse its mask.
        guard inFlight.mutate({ (busy: inout Bool) -> Bool in if busy { return false }; busy = true; return true }) else {
            statsBox.mutate { $0.framesReused += 1 }
            return
        }
        lastSubmitTime = frame.hostTime
        let pixelBuffer = frame.pixelBuffer
        queue.async { [weak self] in self?.run(pixelBuffer, budget: interval) }
    }

    private func run(_ pixelBuffer: CVPixelBuffer, budget: Double) {
        defer { inFlight.set(false) }
        let t0 = hostTimeSeconds()
        do {
            let mask = try segmenter.mask(for: pixelBuffer)
            if let tex = makeTexture(from: mask) { latestMask.set(tex) }
            let ms = (hostTimeSeconds() - t0) * 1000
            ewmaMs = ewmaMs == 0 ? ms : ewmaMs * 0.85 + ms * 0.15
            let now = hostTimeSeconds()
            completions.append(now)
            completions.removeAll { now - $0 > 1 }
            statsBox.mutate {
                $0.inferenceMs = ewmaMs
                $0.effectiveFPS = Double(completions.count)
                $0.lastError = nil
            }
            adapt(budgetMs: budget * 1000)
        } catch {
            statsBox.mutate { $0.lastError = error.localizedDescription }
            Log.ai.error("Segmentation failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Performance ladder: rate → quality → fallback.
    private func adapt(budgetMs: Double) {
        guard ewmaMs > budgetMs * 1.1 else { return }
        var cfg = config.get()
        if cfg.targetFPS > 15 {
            cfg.targetFPS = max(15, cfg.targetFPS / 2)
        } else if cfg.quality == .accurate {
            cfg.quality = .balanced; segmenter.setQuality(.balanced)
        } else if cfg.quality == .balanced {
            cfg.quality = .fast; segmenter.setQuality(.fast)
        } else if cfg.targetFPS > 10 {
            cfg.targetFPS = 10
        } else {
            onFallbackSuggested?()
            return
        }
        config.set(cfg)
        ewmaMs = 0
        statsBox.mutate { $0.quality = cfg.quality; $0.targetFPS = cfg.targetFPS }
        Log.ai.notice("AI adapted: \(cfg.targetFPS) fps, quality \(cfg.quality.rawValue, privacy: .public)")
    }

    /// Thermal manager hook: cap the inference rate.
    func capFPS(_ fps: Int) {
        config.mutate { $0.targetFPS = min($0.targetFPS, fps) }
        statsBox.mutate { $0.targetFPS = min($0.targetFPS, fps) }
    }

    private func makeTexture(from mask: CVPixelBuffer) -> MaskTexture? {
        if CVPixelBufferGetIOSurface(mask) != nil,
           let t = context.textureCache.texture(from: mask, plane: 0, format: .r8Unorm) {
            return MaskTexture(texture: t.texture, keepAlive: t.cvTexture)
        }
        // Not IOSurface-backed: small CPU upload (mask is ~0.2 MP, well under 0.1 ms) into
        // alternating textures so the GPU never reads a texture while it is being overwritten.
        let w = CVPixelBufferGetWidth(mask), h = CVPixelBufferGetHeight(mask)
        if uploadTextures.count != 2 || uploadTextures[0].width != w || uploadTextures[0].height != h {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: w, height: h, mipmapped: false)
            d.usage = [.shaderRead]
            d.storageMode = .shared
            uploadTextures = (0..<2).compactMap { _ in context.device.makeTexture(descriptor: d) }
        }
        guard uploadTextures.count == 2 else { return nil }
        uploadIndex ^= 1
        let tex = uploadTextures[uploadIndex]
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                    withBytes: base, bytesPerRow: CVPixelBufferGetBytesPerRow(mask))
        return MaskTexture(texture: tex, keepAlive: nil)
    }
}
