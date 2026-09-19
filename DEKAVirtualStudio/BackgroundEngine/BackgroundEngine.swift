//
//  BackgroundEngine.swift
//  Virtual backgrounds: solid / gradient (computed in the shader), image (JPG/PNG/HEIF) and
//  looping video. Images are decoded + blurred ONCE off the render thread; video frames are
//  pulled zero-copy from AVPlayerItemVideoOutput each program frame.
//

import Foundation
import AVFoundation
import Metal
import MetalKit
import ImageIO
import QuartzCore

struct BackgroundFrame {
    let texture: MTLTexture
    let keepAlive: AnyObject?
    /// Aspect-fill correction for the shader (see BackgroundSettings / ShaderTypes.h).
    let aspectFix: SIMD2<Float>
}

final class BackgroundEngine {

    private let context: MetalContext
    private let blur: GPUBlur
    private let loadQueue = DispatchQueue(label: "deka.background.load", qos: .userInitiated)
    private let loader: MTKTextureLoader

    /// key = "<asset>|<blurRadius>"
    private let images = Locked<[String: MTLTexture]>([:])
    private let loading = Locked<Set<String>>([])
    private let videos = Locked<[String: VideoBackground]>([:])

    /// Resolves asset names to files (set by ProjectManager).
    var assetURL: (String) -> URL? = { _ in nil }
    var outputAspect: Float = 16.0 / 9.0

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif"]
    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]

    init(context: MetalContext) {
        self.context = context
        self.blur = GPUBlur(context: context)
        self.loader = MTKTextureLoader(device: context.device)
    }

    static func kind(forAsset name: String) -> BackgroundKind? {
        let ext = (name as NSString).pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .image }
        if videoExtensions.contains(ext) { return .video }
        return nil
    }

    // MARK: Render-thread API

    private var browserBackground: WebBrowserBackground?

    private func activeBrowserBackground() -> WebBrowserBackground {
        if let b = browserBackground { return b }
        let b = WebBrowserBackground(context: context)
        browserBackground = b
        return b
    }

    /// Returns the background texture for these settings, or nil if it isn't ready yet
    /// (a load is kicked off; the program shows the shader colour meanwhile — never stalls).
    func frame(for s: BackgroundSettings, commandBuffer: MTLCommandBuffer) -> BackgroundFrame? {
        switch s.kind {
        case .image:
            guard let asset = s.assetName else { return nil }
            let key = "\(asset)|\(Int(s.blur))"
            if let tex = images.get()[key] {
                return BackgroundFrame(texture: tex, keepAlive: nil, aspectFix: aspectFix(tex))
            }
            preloadImage(asset: asset, blurRadius: Int(s.blur))
            return nil
        case .video:
            guard let asset = s.assetName, let video = videoBackground(asset: asset) else { return nil }
            return video.currentFrame(commandBuffer: commandBuffer, blurRadius: Int(s.blur),
                                      blur: blur, context: context, aspect: outputAspect)
        case .browser:
            let browser = activeBrowserBackground()
            browser.load(urlString: s.browserURL, fps: s.browserFPS)
            return browser.currentFrame(commandBuffer: commandBuffer, blurRadius: Int(s.blur),
                                        blur: blur, aspect: outputAspect)
        default:
            return nil
        }
    }

    private func aspectFix(_ t: MTLTexture) -> SIMD2<Float> {
        Self.aspectFill(textureAspect: Float(t.width) / Float(max(t.height, 1)), outputAspect: outputAspect)
    }

    static func aspectFill(textureAspect: Float, outputAspect: Float) -> SIMD2<Float> {
        textureAspect > outputAspect ? SIMD2(outputAspect / textureAspect, 1) : SIMD2(1, textureAspect / outputAspect)
    }

    // MARK: Loading (off the render thread)

    func preload(_ s: BackgroundSettings) {
        switch s.kind {
        case .image:
            guard let asset = s.assetName else { return }
            preloadImage(asset: asset, blurRadius: Int(s.blur))
        case .video:
            guard let asset = s.assetName else { return }
            _ = videoBackground(asset: asset)
        case .browser:
            activeBrowserBackground().load(urlString: s.browserURL, fps: s.browserFPS)
        default:
            break
        }
    }

    private func preloadImage(asset: String, blurRadius: Int) {
        let key = "\(asset)|\(blurRadius)"
        let shouldLoad = loading.mutate { (set: inout Set<String>) -> Bool in
            if set.contains(key) { return false }
            set.insert(key); return true
        }
        guard shouldLoad, images.get()[key] == nil else { return }
        loadQueue.async { [weak self] in
            guard let self else { return }
            defer { self.loading.mutate { $0.remove(key) } }
            do {
                let tex = try self.loadImage(asset: asset, blurRadius: blurRadius)
                self.images.mutate { dict in
                    // Keep memory bounded: at most 6 decoded backgrounds resident.
                    if dict.count >= 6, let victim = dict.keys.first(where: { !$0.hasPrefix(asset + "|") }) { dict[victim] = nil }
                    dict[key] = tex
                }
            } catch {
                Log.pipeline.error("Background load failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func loadImage(asset: String, blurRadius: Int) throws -> MTLTexture {
        guard let url = assetURL(asset) else { throw CocoaError(.fileNoSuchFile) }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { throw CocoaError(.fileReadCorruptFile) }
        // Decode at most 4K on the long edge (HEIF photos can be 48 MP).
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 3840
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // SRGB=false keeps display-encoded values, matching the rest of the (gamma-space) pipeline.
        let base = try loader.newTexture(cgImage: cg, options: [
            .SRGB: false,
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue)
        ])
        guard blurRadius > 0 else { return base }

        // Blur at quarter resolution: a large, smooth blur for ~1/16 of the cost.
        let w = max(base.width / 4, 16), h = max(base.height / 4, 16)
        let small = try context.makeTexture(width: w, height: h, format: .rgba8Unorm, label: "bgSmall")
        let tmp = try context.makeTexture(width: w, height: h, format: .rgba8Unorm, label: "bgTmp")
        let out = try context.makeTexture(width: w, height: h, format: .rgba8Unorm, label: "bgBlur")
        guard let cb = context.queue.makeCommandBuffer() else { return base }
        cb.label = "Background blur"
        blur.resample(cb, source: base, destination: small)
        blur.encode(cb, source: small, temp: tmp, destination: out, radius: max(1, blurRadius / 4))
        cb.commit()
        cb.waitUntilCompleted()   // load queue only — never the render thread
        return out
    }

    private func videoBackground(asset: String) -> VideoBackground? {
        if let v = videos.get()[asset] { return v }
        guard let url = assetURL(asset) else { return nil }
        let v = VideoBackground(url: url)
        videos.mutate { dict in
            // One looping video active at a time keeps decode power low.
            for (k, other) in dict where k != asset { other.stop() }
            dict = [asset: v]
        }
        return v
    }

    func stopVideos() {
        videos.mutate { dict in dict.values.forEach { $0.stop() }; dict.removeAll() }
    }

    func purge() {
        images.set([:])
        stopVideos()
        browserBackground?.stop()
        browserBackground = nil
    }

    func reloadBrowser() {
        browserBackground?.reload()
    }
}

/// A muted, looping video decoded by AVFoundation; frames arrive as IOSurface-backed BGRA.
final class VideoBackground {
    private let player: AVQueuePlayer
    private let looper: AVPlayerLooper
    /// An AVPlayerItemVideoOutput can belong to one item only; AVPlayerLooper plays several
    /// copies of the template item, so each copy gets its own output.
    private var outputs: [ObjectIdentifier: AVPlayerItemVideoOutput] = [:]
    private var last: (tex: MTLTexture, keep: AnyObject)?
    private var blurred: (small: MTLTexture, tmp: MTLTexture, out: MTLTexture)?

    init(url: URL) {
        let item = AVPlayerItem(url: url)
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ]
        player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: player, templateItem: item)
        // AVPlayerLooper plays copies of the template item; attach the output to each copy.
        for copy in looper.loopingPlayerItems {
            let out = AVPlayerItemVideoOutput(pixelBufferAttributes: attrs)
            copy.add(out)
            outputs[ObjectIdentifier(copy)] = out
        }
        player.play()
    }

    func stop() { player.pause() }

    func currentFrame(commandBuffer: MTLCommandBuffer, blurRadius: Int, blur: GPUBlur,
                      context: MetalContext, aspect: Float) -> BackgroundFrame? {
        if let item = player.currentItem, let output = outputs[ObjectIdentifier(item)] {
            let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
            if output.hasNewPixelBuffer(forItemTime: itemTime),
               let pb = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil),
               let t = context.textureCache.texture(from: pb, plane: 0, format: .bgra8Unorm) {
                last = (t.texture, t.cvTexture)
            }
        }
        guard let last else { return nil }
        var tex = last.tex
        if blurRadius > 0 {
            let w = max(tex.width / 4, 16), h = max(tex.height / 4, 16)
            if blurred == nil || blurred!.small.width != w || blurred!.small.height != h {
                if let a = try? context.makeTexture(width: w, height: h, format: .rgba8Unorm, label: "vbgSmall"),
                   let b = try? context.makeTexture(width: w, height: h, format: .rgba8Unorm, label: "vbgTmp"),
                   let c = try? context.makeTexture(width: w, height: h, format: .rgba8Unorm, label: "vbgBlur") {
                    blurred = (a, b, c)
                }
            }
            if let bt = blurred {
                blur.resample(commandBuffer, source: tex, destination: bt.small)
                blur.encode(commandBuffer, source: bt.small, temp: bt.tmp, destination: bt.out, radius: max(1, blurRadius / 4))
                tex = bt.out
            }
        }
        let fix = BackgroundEngine.aspectFill(textureAspect: Float(last.tex.width) / Float(max(last.tex.height, 1)),
                                              outputAspect: aspect)
        return BackgroundFrame(texture: tex, keepAlive: last.keep, aspectFix: fix)
    }
}
