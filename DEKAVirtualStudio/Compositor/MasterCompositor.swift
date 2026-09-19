//
//  MasterCompositor.swift
//  THE single rendering pipeline. Every consumer (monitor, stream, recorder) is fed from the
//  one MASTER frame produced here — there is no second render path.
//
//  Per camera frame (capture thread, ~1 ms CPU):
//    camera CVPixelBuffer ──(CVMetalTextureCache)──► Y + CbCr textures
//    [lane A: incoming scene]  prepareForeground → matte feather → compositeProgram
//    [lane B: outgoing scene]  (only during a FADE)                → mixPrograms
//    MASTER RGB ──packNV12──► IOSurface NV12 CVPixelBuffer ──► sinks (WebRTC / recorder)
//    MASTER RGB ──────────────────────────────────────────────► monitor (CAMetalLayer)
//

import Foundation
import Metal
import CoreVideo
import CoreMedia

struct CompositorStats: Equatable {
    var fps: Double = 0
    var gpuMs: Double = 0
    var cpuEncodeMs: Double = 0
    var droppedFrames: Int = 0          // total, all causes
    var droppedCamera: Int = 0          // AVFoundation dropped (late)
    var droppedGPUBusy: Int = 0         // GPU still busy with previous frames
    var droppedPoolExhausted: Int = 0   // encoder / recorder holding every buffer
    var gpuErrors: Int = 0
    var outputSize: CGSize = .zero
}

final class MasterCompositor: CameraFrameConsumer {

    // Dependencies
    let context: MetalContext
    let renderer: MetalRenderer
    private let scenes: SceneEngine
    private let backgrounds: BackgroundEngine
    private let graphics: GraphicsEngine
    private let segmentation: SegmentationEngine
    private let blur: GPUBlur
    private let lutLibrary: LUTLibrary

    // Output
    private let sinks = Locked<[ObjectIdentifier: MasterFrameSink]>([:])
    private let deliveryQueue = DispatchQueue(label: "deka.master.delivery", qos: .userInteractive)

    // Configuration read by the render thread
    struct Config: Equatable {
        var outputSize = CGSize(width: 1920, height: 1080)
        var rotate180 = false
        var mirror = false
    }
    let config = Locked(Config())

    // Frame pacing: at most 3 frames in flight on the GPU.
    private let inFlight = DispatchSemaphore(value: 3)

    // Render-thread-owned resources (only touched on the capture queue)
    private struct Lane {
        var fg: MTLTexture
        var matteRaw: MTLTexture
        var matteTmp: MTLTexture
        var matteSoft: MTLTexture
        var program: MTLTexture
    }
    private var lanes: [Lane] = []
    private var master: MTLTexture?
    private var lumaSmall: MTLTexture?
    private var lumaTmp: MTLTexture?
    private var lumaBlur: MTLTexture?
    private var outputPool: PixelBufferPool?
    private var allocatedSize: CGSize = .zero

    // LUT textures, loaded off-thread, read on the render thread
    private let loadedLUTs = Locked<[String: LoadedLUT]>([:])
    private let lutLoading = Locked<Set<String>>([])
    private let lutQueue = DispatchQueue(label: "deka.lut.load", qos: .userInitiated)

    // Stats
    private let statsBox = Locked(CompositorStats())
    private var completedTimes: [Double] = []
    private let completedLock = Locked(0)
    var stats: CompositorStats { statsBox.get() }

    init(context: MetalContext, scenes: SceneEngine, backgrounds: BackgroundEngine, graphics: GraphicsEngine,
         segmentation: SegmentationEngine, lutLibrary: LUTLibrary) {
        self.context = context
        self.renderer = MetalRenderer(context: context)
        self.scenes = scenes
        self.backgrounds = backgrounds
        self.graphics = graphics
        self.segmentation = segmentation
        self.lutLibrary = lutLibrary
        self.blur = GPUBlur(context: context)
    }

    // MARK: Sinks

    func addSink(_ sink: MasterFrameSink) { sinks.mutate { $0[ObjectIdentifier(sink)] = sink } }
    func removeSink(_ sink: MasterFrameSink) { sinks.mutate { $0[ObjectIdentifier(sink)] = nil } }
    func hasSink(_ sink: MasterFrameSink) -> Bool { sinks.get()[ObjectIdentifier(sink)] != nil }

    // MARK: LUT residency

    /// Parse + upload a LUT off the render thread so switching LUTs live never drops a frame.
    func warmLUT(id: String?) {
        guard let id, loadedLUTs.get()[id] == nil else { return }
        let start = lutLoading.mutate { (set: inout Set<String>) -> Bool in set.insert(id).inserted }
        guard start else { return }
        lutQueue.async { [weak self] in
            guard let self else { return }
            defer { self.lutLoading.mutate { _ = $0.remove(id) } }
            do {
                let lut = try self.lutLibrary.load(id: id)
                self.loadedLUTs.mutate { $0[id] = lut }
            } catch {
                Log.pipeline.error("LUT load failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func evictLUT(id: String) { loadedLUTs.mutate { $0[id] = nil } }

    // MARK: CameraFrameConsumer (capture thread)

    func cameraDidDropFrame(reason: String) {
        statsBox.mutate { $0.droppedCamera += 1; $0.droppedFrames += 1 }
    }

    func camera(didOutput frame: CameraFrame) {
        let t0 = hostTimeSeconds()

        // Never queue work behind a busy GPU: drop instead (keeps latency constant).
        guard inFlight.wait(timeout: .now()) == .success else {
            statsBox.mutate { $0.droppedGPUBusy += 1; $0.droppedFrames += 1 }
            return
        }
        var committed = false
        defer { if !committed { inFlight.signal() } }

        let cfg = config.get()
        do { try ensureResources(size: cfg.outputSize) } catch {
            Log.pipeline.error("Resource allocation failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let pool = outputPool, let master else { return }

        let pb = frame.pixelBuffer
        guard let yTex = context.textureCache.texture(from: pb, plane: 0, format: .r8Unorm),
              let cTex = context.textureCache.texture(from: pb, plane: 1, format: .rg8Unorm) else { return }

        let sceneState = scenes.renderState(at: frame.hostTime)
        let usesAI = sceneState.incoming.keyMode == .aiCutout || sceneState.outgoing?.keyMode == .aiCutout
        if usesAI { segmentation.submit(frame) }

        guard let outBuffer = pool.makeBuffer() else {
            statsBox.mutate { $0.droppedPoolExhausted += 1; $0.droppedFrames += 1 }
            return
        }
        guard let outY = context.textureCache.texture(from: outBuffer, plane: 0, format: .r8Unorm, writable: true),
              let outC = context.textureCache.texture(from: outBuffer, plane: 1, format: .rg8Unorm, writable: true),
              let cb = context.queue.makeCommandBuffer() else { return }
        cb.label = "Master frame"

        var keepAlive: [AnyObject] = [yTex.cvTexture, cTex.cvTexture, outY.cvTexture, outC.cvTexture, pb, outBuffer]

        // Base uniforms shared by both lanes
        var base = DEKAFrameUniforms()
        let decode = ColorEngine.decode(for: pb)
        base.yuvToRgb = decode.matrix
        base.yuvOffset = decode.offset
        base.yuvScale = decode.scale
        base.rotate180 = cfg.rotate180 ? 1 : 0
        base.mirror = cfg.mirror ? 1 : 0
        base.outputSize = SIMD2(Float(cfg.outputSize.width), Float(cfg.outputSize.height))
        let camAspect = Float(CVPixelBufferGetWidth(pb)) / Float(max(CVPixelBufferGetHeight(pb), 1))
        let outAspect = Float(cfg.outputSize.width / cfg.outputSize.height)
        base.srcAspectFix = BackgroundEngine.aspectFill(textureAspect: camAspect, outputAspect: outAspect)

        // Midtone detail needs a blurred luma image (quarter resolution); only when used.
        let needsDetail = sceneState.incoming.color.midtoneDetail != 0 || (sceneState.outgoing?.color.midtoneDetail ?? 0) != 0
        var lumaForShader: MTLTexture = context.dummy2D
        if needsDetail, let small = lumaSmall, let tmp = lumaTmp, let out = lumaBlur {
            blur.resample(cb, source: yTex.texture, destination: small)
            blur.encode(cb, source: small, temp: tmp, destination: out, radius: 6)
            lumaForShader = out
        }

        // Lane A = incoming scene
        var uniformsA = base
        let matteA = encodeLane(scene: sceneState.incoming, lane: lanes[0], cb: cb, y: yTex.texture, c: cTex.texture,
                   luma: lumaForShader, uniforms: &uniformsA, time: frame.hostTime, keepAlive: &keepAlive)
        var programTexture = lanes[0].program

        // Lane B = outgoing scene (FADE only), then mix into MASTER
        if let outgoing = sceneState.outgoing {
            var uniformsB = base
            _ = encodeLane(scene: outgoing, lane: lanes[1], cb: cb, y: yTex.texture, c: cTex.texture,
                       luma: lumaForShader, uniforms: &uniformsB, time: frame.hostTime, keepAlive: &keepAlive)
            var mixU = base
            mixU.transitionMix = sceneState.mix
            if let enc = cb.makeComputeCommandEncoder() {
                enc.label = "Transition mix"
                enc.setComputePipelineState(context.mixPrograms)
                enc.setTexture(lanes[1].program, index: 0)
                enc.setTexture(lanes[0].program, index: 1)
                enc.setTexture(master, index: 2)
                enc.setBytes(&mixU, length: MemoryLayout<DEKAFrameUniforms>.stride, index: 0)
                context.dispatch(enc, pipeline: context.mixPrograms, width: master.width, height: master.height)
                enc.endEncoding()
            }
            programTexture = master
        }

        // MASTER → NV12 (encoder native, zero copy)
        if let enc = cb.makeComputeCommandEncoder() {
            enc.label = "Pack NV12"
            enc.setComputePipelineState(context.packNV12)
            enc.setTexture(programTexture, index: 0)
            enc.setTexture(outY.texture, index: 1)
            enc.setTexture(outC.texture, index: 2)
            context.dispatch(enc, pipeline: context.packNV12, width: outC.texture.width, height: outC.texture.height)
            enc.endEncoding()
        }

        // Operator monitor (skipped automatically if the screen can't keep up).
        renderer.encode(into: cb, program: programTexture, matte: matteA,
                        yPlane: yTex.texture, cPlane: cTex.texture, uniforms: &uniformsA)

        let pts = frame.presentationTime
        let cameraBuffer = pb
        let finalTexture = programTexture
        let cpuMs = (hostTimeSeconds() - t0) * 1000
        let retainedResources = keepAlive
        cb.addCompletedHandler { [weak self] buffer in
            withExtendedLifetime(retainedResources) {}   // resources live until the GPU is done
            guard let self else { return }
            self.inFlight.signal()
            let gpuMs = (buffer.gpuEndTime - buffer.gpuStartTime) * 1000
            self.recordCompletion(gpuMs: gpuMs, cpuMs: cpuMs, error: buffer.error)
            guard buffer.status == .completed else { return }
            let masterFrame = MasterFrame(pixelBuffer: outBuffer, texture: finalTexture,
                                          presentationTime: pts, sourceCamera: cameraBuffer)
            let targets = Array(self.sinks.get().values)
            guard !targets.isEmpty else { return }
            self.deliveryQueue.async { targets.forEach { $0.consume(master: masterFrame) } }
        }
        cb.commit()
        committed = true
    }

    // MARK: Lane encoding

    private func encodeLane(scene: SceneModel, lane: Lane, cb: MTLCommandBuffer, y: MTLTexture, c: MTLTexture,
                            luma: MTLTexture, uniforms u: inout DEKAFrameUniforms, time: Double,
                            keepAlive: inout [AnyObject]) -> MTLTexture {
        // Foreground transform
        u.fgScale = SIMD2(repeating: max(scene.transform.scale, 0.05))
        u.fgOffset = SIMD2(scene.transform.positionX, scene.transform.positionY)

        // Colour
        ColorEngine.apply(scene.color, to: &u)

        // LUT (only if already resident — otherwise warm it and render without for a frame or two)
        var lutTexture = context.identityLUT
        u.lutEnabled = 0
        if scene.lut.enabled, let id = scene.lut.lutID {
            if let loaded = loadedLUTs.get()[id] {
                lutTexture = loaded.texture
                u.lutEnabled = 1
                u.lutSize = Float(loaded.lut.size)
                u.lutIntensity = scene.lut.intensity
                u.lutDomainMin = loaded.lut.domainMin
                u.lutDomainMax = loaded.lut.domainMax
            } else {
                warmLUT(id: id)
            }
        }
        if u.lutEnabled == 0 { u.lutSize = 2; u.lutDomainMin = .zero; u.lutDomainMax = .one }

        // Key / AI
        var keyMode = scene.keyMode
        var maskTexture = context.dummyMask
        if keyMode == .aiCutout {
            if let mask = segmentation.currentMask() {
                maskTexture = mask.texture
                if let k = mask.keepAlive { keepAlive.append(k) }
            } else {
                keyMode = .off   // first frames before the first mask: show the camera, never garbage
            }
        }
        ChromaKeyEngine.apply(mode: keyMode, chroma: scene.chroma, to: &u)

        // Background
        let bg = scene.background
        var bgTexture = context.dummy2D
        u.bgColorA = bg.colorA.simd
        u.bgColorB = bg.colorB.simd
        u.bgGradientAngle = bg.gradientAngle * .pi / 180
        u.bgScale = SIMD2(repeating: max(bg.scale, 0.05))
        u.bgOffset = SIMD2(bg.positionX, bg.positionY)
        u.bgOpacity = bg.opacity
        u.bgBrightness = bg.brightness
        u.bgContrast = bg.contrast
        u.bgAspectFix = SIMD2(1, 1)
        switch bg.kind {
        case .none: u.bgType = Int32(DEKA_BG_NONE)
        case .solid: u.bgType = Int32(DEKA_BG_SOLID)
        case .gradient: u.bgType = Int32(DEKA_BG_GRADIENT)
        case .image, .video:
            if let frame = backgrounds.frame(for: bg, commandBuffer: cb) {
                bgTexture = frame.texture
                u.bgAspectFix = frame.aspectFix
                u.bgType = Int32(DEKA_BG_TEXTURE)
                if let k = frame.keepAlive { keepAlive.append(k) }
            } else {
                u.bgType = Int32(DEKA_BG_SOLID)   // still loading: show colour A, never stall
            }
        }
        u.shadowOpacity = keyMode == .off ? 0 : bg.shadowOpacity
        u.shadowOffset = SIMD2(bg.shadowOffsetX, bg.shadowOffsetY)
        u.lightWrap = keyMode == .off ? 0 : bg.lightWrap

        // Graphics
        var gfxTexture = context.dummy2D
        var tickerTexture = context.dummy2D
        u.graphicsEnabled = 0
        u.tickerEnabled = 0
        if let layer = graphics.layer(for: scene.id) {
            gfxTexture = layer.texture
            keepAlive.append(contentsOf: layer.keepAlive)
            u.graphicsEnabled = 1
        }
        if scene.graphics.ticker.enabled, let ticker = graphics.ticker(for: scene.id) {
            tickerTexture = ticker.texture
            keepAlive.append(contentsOf: ticker.keepAlive)
            u.tickerEnabled = 1
            u.tickerRect = GraphicsEngine.tickerRect
            u.tickerStripAspect = ticker.stripAspect
            let size = CGSize(width: CGFloat(u.outputSize.x), height: CGFloat(u.outputSize.y))
            u.tickerScroll = GraphicsEngine.tickerScroll(time: time, speed: scene.graphics.ticker.speed,
                                                         outputSize: size, stripAspect: ticker.stripAspect)
        }

        // Pass 1: foreground + raw matte
        guard let enc = cb.makeComputeCommandEncoder() else { return lane.matteRaw }
        enc.label = "Prepare \(scene.name)"
        enc.setComputePipelineState(context.prepareForeground)
        enc.setTexture(y, index: 0)
        enc.setTexture(c, index: 1)
        enc.setTexture(maskTexture, index: 2)
        enc.setTexture(luma, index: 3)
        enc.setTexture(lutTexture, index: 4)
        enc.setTexture(lane.fg, index: 5)
        enc.setTexture(lane.matteRaw, index: 6)
        enc.setBytes(&u, length: MemoryLayout<DEKAFrameUniforms>.stride, index: 0)
        context.dispatch(enc, pipeline: context.prepareForeground, width: lane.fg.width, height: lane.fg.height)
        enc.endEncoding()

        // Pass 2: feather (only when keying and feather > 0)
        var matte = lane.matteRaw
        let feather = Int(scene.chroma.feather.rounded())
        if keyMode != .off, feather > 0 {
            blur.encode(cb, source: lane.matteRaw, temp: lane.matteTmp, destination: lane.matteSoft, radius: feather)
            matte = lane.matteSoft
        }

        // Pass 3: composite → lane program
        guard let comp = cb.makeComputeCommandEncoder() else { return matte }
        comp.label = "Composite \(scene.name)"
        comp.setComputePipelineState(context.compositeProgram)
        comp.setTexture(lane.fg, index: 0)
        comp.setTexture(matte, index: 1)
        comp.setTexture(bgTexture, index: 2)
        comp.setTexture(gfxTexture, index: 3)
        comp.setTexture(tickerTexture, index: 4)
        comp.setTexture(lane.program, index: 5)
        comp.setBytes(&u, length: MemoryLayout<DEKAFrameUniforms>.stride, index: 0)
        context.dispatch(comp, pipeline: context.compositeProgram, width: lane.program.width, height: lane.program.height)
        comp.endEncoding()
        return matte
    }

    // MARK: Resources

    private func ensureResources(size: CGSize) throws {
        guard size != allocatedSize || lanes.isEmpty else { return }
        let w = Int(size.width), h = Int(size.height)
        func lane(_ i: Int) throws -> Lane {
            Lane(fg: try context.makeTexture(width: w, height: h, format: .rgba16Float, label: "fg\(i)"),
                 matteRaw: try context.makeTexture(width: w, height: h, format: .r16Float, label: "matteRaw\(i)"),
                 matteTmp: try context.makeTexture(width: w, height: h, format: .r16Float, label: "matteTmp\(i)"),
                 matteSoft: try context.makeTexture(width: w, height: h, format: .r16Float, label: "matteSoft\(i)"),
                 program: try context.makeTexture(width: w, height: h, format: .rgba8Unorm, label: "program\(i)"))
        }
        lanes = [try lane(0), try lane(1)]
        master = try context.makeTexture(width: w, height: h, format: .rgba8Unorm, label: "MASTER")
        lumaSmall = try context.makeTexture(width: w / 4, height: h / 4, format: .r16Float, label: "lumaSmall")
        lumaTmp = try context.makeTexture(width: w / 4, height: h / 4, format: .r16Float, label: "lumaTmp")
        lumaBlur = try context.makeTexture(width: w / 4, height: h / 4, format: .r16Float, label: "lumaBlur")
        outputPool = try PixelBufferPool(width: w, height: h, pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        allocatedSize = size
        statsBox.mutate { $0.outputSize = size }
        Log.pipeline.info("Allocated pipeline \(w)x\(h)")
    }

    private func recordCompletion(gpuMs: Double, cpuMs: Double, error: Error?) {
        let now = hostTimeSeconds()
        let fps: Double = completedLock.mutate { (_: inout Int) -> Double in
            completedTimes.append(now)
            if let first = completedTimes.first, now - first > 1.0 {
                completedTimes.removeAll { now - $0 > 1.0 }
            }
            return Double(completedTimes.count)
        }
        statsBox.mutate { s in
            s.fps = fps
            s.gpuMs = s.gpuMs == 0 ? gpuMs : s.gpuMs * 0.9 + gpuMs * 0.1
            s.cpuEncodeMs = s.cpuEncodeMs == 0 ? cpuMs : s.cpuEncodeMs * 0.9 + cpuMs * 0.1
            if error != nil { s.gpuErrors += 1 }
        }
        if let error { Log.metal.error("GPU error: \(error.localizedDescription, privacy: .public)") }
    }

    func handleMemoryWarning() {
        context.textureCache.flush()
        outputPool?.flush()
        backgrounds.purge()
    }
}
