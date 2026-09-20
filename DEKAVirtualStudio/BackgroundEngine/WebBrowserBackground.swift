//
//  WebBrowserBackground.swift
//  Renders a live web page (URL) as an offscreen virtual background texture for the Metal compositor.
//  Keeps live broadcast 100% stable with asynchronous snapshotting, double-buffering, and zero render stalls.
//

import Foundation
import WebKit
import Metal
import MetalKit

final class WebBrowserBackground: NSObject, WKNavigationDelegate, @unchecked Sendable {

    private let context: MetalContext
    private let textureLoader: MTKTextureLoader
    private var webView: WKWebView?
    private var captureTask: Task<Void, Never>?
    private let textureBox = Locked<MTLTexture?>(nil)
    private let currentURLString = Locked<String>("")
    private var blurred: (small: MTLTexture, tmp: MTLTexture, out: MTLTexture)?
    private var isCapturing = false

    init(context: MetalContext) {
        self.context = context
        self.textureLoader = MTKTextureLoader(device: context.device)
        super.init()
    }

    func load(urlString: String, fps: Int = 30) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let validURLString = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        if currentURLString.get() == validURLString { return }
        currentURLString.set(validURLString)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.setupWebView(with: validURLString, fps: fps)
        }
    }

    @MainActor
    private func setupWebView(with urlString: String, fps: Int) {
        if webView == nil {
            let config = WKWebViewConfiguration()
            config.allowsInlineMediaPlayback = true
            config.mediaTypesRequiringUserActionForPlayback = []

            let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
            let wv = WKWebView(frame: frame, configuration: config)
            wv.isOpaque = true
            wv.navigationDelegate = self
            wv.scrollView.isScrollEnabled = false
            self.webView = wv
        }

        if let url = URL(string: urlString) {
            webView?.load(URLRequest(url: url))
        }

        startCaptureLoop(fps: fps)
    }

    @MainActor
    private func startCaptureLoop(fps: Int) {
        captureTask?.cancel()
        let intervalNs = UInt64(1_000_000_000 / max(fps, 1))

        captureTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNs)
                guard let self else { break }
                await self.captureFrame()
            }
        }
    }

    @MainActor
    private func captureFrame() async {
        guard let wv = webView, wv.bounds.width > 0 else { return }
        let snapConfig = WKSnapshotConfiguration()
        snapConfig.snapshotWidth = 1920

        do {
            let image = try await wv.takeSnapshot(configuration: snapConfig)
            guard let cgImage = image.cgImage else { return }

            let texture = try? await textureLoader.newTexture(cgImage: cgImage, options: [
                .SRGB: false,
                .generateMipmaps: false
            ])
            if let texture {
                textureBox.set(texture)
            }
        } catch {
            // Snapshot skipped this frame, previous valid texture will remain active
        }
    }

    func currentFrame(commandBuffer: MTLCommandBuffer, blurRadius: Int, blur: GPUBlur, aspect: Float) -> BackgroundFrame? {
        guard let tex = textureBox.get() else { return nil }
        var outTex = tex
        if blurRadius > 0 {
            let w = max(tex.width / 4, 16), h = max(tex.height / 4, 16)
            if blurred == nil || blurred!.small.width != w || blurred!.small.height != h {
                if let a = try? context.makeTexture(width: w, height: h, format: .rgba8Unorm, label: "browserSmall"),
                   let b = try? context.makeTexture(width: w, height: h, format: .rgba8Unorm, label: "browserTmp"),
                   let c = try? context.makeTexture(width: w, height: h, format: .rgba8Unorm, label: "browserBlur") {
                    blurred = (a, b, c)
                }
            }
            if let bt = blurred {
                blur.resample(commandBuffer, source: tex, destination: bt.small)
                blur.encode(commandBuffer, source: bt.small, temp: bt.tmp, destination: bt.out, radius: max(1, blurRadius / 4))
                outTex = bt.out
            }
        }
        let fix = BackgroundEngine.aspectFill(textureAspect: Float(tex.width) / Float(max(tex.height, 1)), outputAspect: aspect)
        return BackgroundFrame(texture: outTex, keepAlive: nil, aspectFix: fix)
    }

    func reload() {
        DispatchQueue.main.async { [weak self] in
            self?.webView?.reload()
        }
    }

    func stop() {
        captureTask?.cancel()
        captureTask = nil
        currentURLString.set("")
        DispatchQueue.main.async { [weak self] in
            self?.webView?.stopLoading()
            self?.webView = nil
        }
        textureBox.set(nil)
        blurred = nil
    }

    // Ignore SSL errors for local intranet/dashboards
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
