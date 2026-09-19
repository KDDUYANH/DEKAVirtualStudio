//
//  GraphicsEngine.swift
//  Logo, watermark, text, lower third, clock, countdown → one premultiplied BGRA layer.
//  Ticker → a separate text strip scrolled by the GPU.
//
//  Cost model: text is rasterised with Core Text only when something changes (or once per
//  second while a clock/countdown is visible), straight into an IOSurface pixel buffer that the
//  compositor samples zero-copy. Nothing is drawn on the CPU per video frame.
//

import UIKit
import CoreVideo
import Metal

struct GraphicsLayer {
    let texture: MTLTexture
    let keepAlive: [AnyObject]
}

struct TickerLayer {
    let texture: MTLTexture
    let keepAlive: [AnyObject]
    let stripAspect: Float        // strip width / height in pixels
}

final class GraphicsEngine {

    static let tickerRect = SIMD4<Float>(0, 0.925, 1, 0.055)   // x, y, w, h (normalised)

    private let context: MetalContext
    private let queue = DispatchQueue(label: "deka.graphics", qos: .userInitiated)
    private var pool: PixelBufferPool?
    private var outputSize = CGSize(width: 1920, height: 1080)

    private struct Entry { var settings: GraphicsSettings; var layer: GraphicsLayer?; var ticker: TickerLayer?; var tickerText: String }
    private let entries = Locked<[UUID: Entry]>([:])
    private var logoCache: [String: UIImage] = [:]
    private var timer: DispatchSourceTimer?

    var assetURL: (String) -> URL? = { _ in nil }

    init(context: MetalContext) {
        self.context = context
        startClock()
    }

    func setOutputSize(_ size: CGSize) {
        queue.async {
            guard size != self.outputSize || self.pool == nil else { return }
            self.outputSize = size
            self.pool = try? PixelBufferPool(width: Int(size.width), height: Int(size.height),
                                             pixelFormat: kCVPixelFormatType_32BGRA, minimumBuffers: 3, maximumBuffers: 8)
            let all = self.entries.get()
            for (id, e) in all { self.render(sceneID: id, settings: e.settings, force: true) }
        }
    }

    // MARK: API

    /// Called when a scene's graphics change. Rendering is asynchronous.
    func update(sceneID: UUID, settings: GraphicsSettings) {
        queue.async { self.render(sceneID: sceneID, settings: settings, force: false) }
    }

    /// Keep only these scenes' layers resident (active + transition partner).
    func retain(sceneIDs: Set<UUID>) {
        entries.mutate { dict in dict = dict.filter { sceneIDs.contains($0.key) } }
    }

    func layer(for sceneID: UUID) -> GraphicsLayer? { entries.get()[sceneID]?.layer }
    func ticker(for sceneID: UUID) -> TickerLayer? { entries.get()[sceneID]?.ticker }
    func settings(for sceneID: UUID) -> GraphicsSettings? { entries.get()[sceneID]?.settings }

    func hasVisibleContent(_ s: GraphicsSettings) -> Bool {
        (s.logoEnabled && s.logoAsset != nil) || !s.watermarkText.isEmpty || (s.textEnabled && !s.text.isEmpty)
            || s.lowerThird.enabled || s.clockEnabled || s.countdownEnabled || s.ticker.enabled
    }

    // MARK: Rendering (graphics queue)

    private func startClock() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(50))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            for (id, e) in self.entries.get() where e.settings.clockEnabled || e.settings.countdownEnabled {
                self.render(sceneID: id, settings: e.settings, force: true)
            }
        }
        t.resume()
        timer = t
    }

    private func render(sceneID: UUID, settings: GraphicsSettings, force: Bool) {
        let previous = entries.get()[sceneID]
        if !force, let previous, previous.settings == settings, previous.layer != nil { return }
        if pool == nil {
            pool = try? PixelBufferPool(width: Int(outputSize.width), height: Int(outputSize.height),
                                        pixelFormat: kCVPixelFormatType_32BGRA, minimumBuffers: 3, maximumBuffers: 8)
        }

        var layer: GraphicsLayer? = nil
        if hasVisibleContent(settings), let pool, let pb = pool.makeBuffer() {
            draw(settings: settings, into: pb)
            if let t = context.textureCache.texture(from: pb, plane: 0, format: .bgra8Unorm) {
                layer = GraphicsLayer(texture: t.texture, keepAlive: [pb, t.cvTexture])
            }
        }

        var ticker = previous?.ticker
        var tickerText = previous?.tickerText ?? ""
        if settings.ticker.enabled {
            if ticker == nil || tickerText != settings.ticker.text {
                ticker = makeTicker(text: settings.ticker.text)
                tickerText = settings.ticker.text
            }
        } else {
            ticker = nil
        }
        entries.mutate { $0[sceneID] = Entry(settings: settings, layer: layer, ticker: ticker, tickerText: tickerText) }
    }

    private func withContext(_ pb: CVPixelBuffer, clear: Bool = true, _ body: (CGContext, CGSize) -> Void) {
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb)
        guard let base = CVPixelBufferGetBaseAddress(pb),
              let ctx = CGContext(data: base, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return }
        if clear { ctx.clear(CGRect(x: 0, y: 0, width: w, height: h)) }
        // UIKit-style top-left origin so text and images draw upright.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(ctx)
        body(ctx, CGSize(width: w, height: h))
        UIGraphicsPopContext()
    }

    private func draw(settings s: GraphicsSettings, into pb: CVPixelBuffer) {
        withContext(pb) { ctx, size in
            let W = size.width, H = size.height
            let margin = W * 0.035
            let scale = H / 1080

            // Ticker background bar (text strip is composited by the GPU on top).
            if s.ticker.enabled {
                let r = GraphicsEngine.tickerRect
                ctx.setFillColor(UIColor(white: 0.04, alpha: 0.82).cgColor)
                ctx.fill(CGRect(x: CGFloat(r.x) * W, y: CGFloat(r.y) * H, width: CGFloat(r.z) * W, height: CGFloat(r.w) * H))
            }

            // Logo
            if s.logoEnabled, let name = s.logoAsset, let img = logo(named: name) {
                let lw = W * CGFloat(s.logoScale)
                let lh = lw * img.size.height / max(img.size.width, 1)
                let x: CGFloat = (s.logoPosition == .topLeft || s.logoPosition == .bottomLeft) ? margin : W - margin - lw
                let y: CGFloat = (s.logoPosition == .topLeft || s.logoPosition == .topRight) ? margin : H - margin - lh
                img.draw(in: CGRect(x: x, y: y, width: lw, height: lh), blendMode: .normal, alpha: CGFloat(s.logoOpacity))
            }

            // Lower third
            if s.lowerThird.enabled {
                let lt = s.lowerThird
                let titleFont = UIFont.systemFont(ofSize: 54 * scale, weight: .bold)
                let subFont = UIFont.systemFont(ofSize: 32 * scale, weight: .medium)
                let title = NSAttributedString(string: lt.title, attributes: [.font: titleFont, .foregroundColor: UIColor.white])
                let sub = NSAttributedString(string: lt.subtitle, attributes: [.font: subFont, .foregroundColor: UIColor(white: 0.85, alpha: 1)])
                let pad = 24 * scale
                let boxW = max(title.size().width, sub.size().width) + pad * 2
                let boxH = title.size().height + sub.size().height + pad * 1.6
                let bottom = s.ticker.enabled ? H * CGFloat(GraphicsEngine.tickerRect.y) - margin * 0.6 : H - margin * 1.6
                let box = CGRect(x: margin, y: bottom - boxH, width: boxW, height: boxH)
                ctx.setFillColor(UIColor(white: 0.05, alpha: 0.78).cgColor)
                ctx.fill(box)
                ctx.setFillColor(lt.accent.cgColor)
                ctx.fill(CGRect(x: box.minX, y: box.minY, width: 8 * scale, height: box.height))
                title.draw(at: CGPoint(x: box.minX + pad, y: box.minY + pad * 0.7))
                sub.draw(at: CGPoint(x: box.minX + pad, y: box.minY + pad * 0.7 + title.size().height))
            }

            // Free text (centre-top)
            if s.textEnabled, !s.text.isEmpty {
                let font = UIFont.systemFont(ofSize: CGFloat(s.textSize) * scale, weight: .heavy)
                let shadow = NSShadow(); shadow.shadowBlurRadius = 8 * scale; shadow.shadowColor = UIColor(white: 0, alpha: 0.6)
                let text = NSAttributedString(string: s.text, attributes: [.font: font, .foregroundColor: UIColor.white, .shadow: shadow])
                let ts = text.size()
                text.draw(at: CGPoint(x: (W - ts.width) / 2, y: H * 0.12))
            }

            // Clock / countdown (top-left, stacked)
            var y = margin
            let hudFont = UIFont.monospacedDigitSystemFont(ofSize: 34 * scale, weight: .semibold)
            func hud(_ string: String) {
                let a = NSAttributedString(string: string, attributes: [.font: hudFont, .foregroundColor: UIColor.white])
                let sz = a.size()
                let r = CGRect(x: margin, y: y, width: sz.width + 28 * scale, height: sz.height + 12 * scale)
                ctx.setFillColor(UIColor(white: 0.05, alpha: 0.7).cgColor)
                ctx.fill(r)
                a.draw(at: CGPoint(x: r.minX + 14 * scale, y: r.minY + 6 * scale))
                y = r.maxY + 10 * scale
            }
            if s.clockEnabled { hud(Self.clockFormatter.string(from: Date())) }
            if s.countdownEnabled, let target = s.countdownTarget {
                hud(Self.countdownString(remaining: target.timeIntervalSinceNow))
            }

            // Watermark (bottom-right, subtle)
            if !s.watermarkText.isEmpty {
                let font = UIFont.systemFont(ofSize: 24 * scale, weight: .semibold)
                let a = NSAttributedString(string: s.watermarkText, attributes: [.font: font, .foregroundColor: UIColor(white: 1, alpha: 0.45)])
                let sz = a.size()
                let bottom = s.ticker.enabled ? H * CGFloat(GraphicsEngine.tickerRect.y) - 12 * scale : H - margin
                a.draw(at: CGPoint(x: W - margin - sz.width, y: bottom - sz.height))
            }
        }
    }

    private func makeTicker(text: String) -> TickerLayer? {
        let height = Int(outputSize.height * CGFloat(Self.tickerRect.w))
        let font = UIFont.systemFont(ofSize: CGFloat(height) * 0.55, weight: .semibold)
        let attr = NSAttributedString(string: text + "     ", attributes: [.font: font, .foregroundColor: UIColor.white])
        let width = max(Int(ceil(attr.size().width)), height)
        let attrs: [String: Any] = [kCVPixelBufferMetalCompatibilityKey as String: true,
                                    kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()]
        var pb: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb) == kCVReturnSuccess,
              let pb else { return nil }
        withContext(pb) { _, size in
            let ts = attr.size()
            attr.draw(at: CGPoint(x: 0, y: (size.height - ts.height) / 2))
        }
        guard let t = context.textureCache.texture(from: pb, plane: 0, format: .bgra8Unorm) else { return nil }
        return TickerLayer(texture: t.texture, keepAlive: [pb, t.cvTexture], stripAspect: Float(width) / Float(height))
    }

    private func logo(named name: String) -> UIImage? {
        if let img = logoCache[name] { return img }
        guard let url = assetURL(name), let img = UIImage(contentsOfFile: url.path) else { return nil }
        logoCache[name] = img
        return img
    }

    func invalidateAsset(_ name: String) { queue.async { self.logoCache[name] = nil } }

    // MARK: Formatting

    static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static func countdownString(remaining: TimeInterval) -> String {
        let s = max(0, Int(remaining.rounded(.up)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%ld:%02ld:%02ld", h, m, sec) : String(format: "%02ld:%02ld", m, sec)
    }

    /// Ticker scroll (normalised strip offset) for a given time. Pure function, unit tested.
    static func tickerScroll(time: Double, speed: Float, outputSize: CGSize, stripAspect: Float) -> Float {
        let rectH = Double(outputSize.height) * Double(tickerRect.w)
        let stripW = Double(stripAspect) * rectH
        guard stripW > 0 else { return 0 }
        let pxPerSecond = Double(speed) * Double(outputSize.width)
        let u = (time * pxPerSecond / stripW).truncatingRemainder(dividingBy: 1)
        return Float(u)
    }
}
