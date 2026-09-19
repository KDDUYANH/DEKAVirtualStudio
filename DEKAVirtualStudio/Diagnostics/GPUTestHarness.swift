//
//  GPUTestHarness.swift
//  Runs the REAL production kernels on synthetic frames with known colours and reads the
//  result back. Used by SYSTEM CHECK on the device and by the XCTest suite.
//

import Foundation
import Metal
import CoreVideo
import simd

final class GPUTestHarness {

    let context: MetalContext
    let width = 64
    let height = 36

    init(context: MetalContext) { self.context = context }

    /// Neutral uniforms (no grade, no LUT, no key) for a 709 full-range source.
    func neutralUniforms() -> DEKAFrameUniforms {
        var u = DEKAFrameUniforms()
        let d = ColorEngine.decode(matrixName: kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String, fullRange: true)
        u.yuvToRgb = d.matrix
        u.yuvOffset = d.offset
        u.yuvScale = d.scale
        u.fgScale = SIMD2(1, 1)
        u.srcAspectFix = SIMD2(1, 1)
        u.outputSize = SIMD2(Float(width), Float(height))
        ColorEngine.apply(.neutral, to: &u)
        u.colorEnabled = 0
        u.lutEnabled = 0
        u.lutSize = 2
        u.lutDomainMax = SIMD3(repeating: 1)
        ChromaKeyEngine.apply(mode: .off, chroma: ChromaSettings(), to: &u)
        return u
    }

    /// Solid-colour NV12 (full range, BT.709) IOSurface buffer — what the camera delivers.
    func makeCameraBuffer(rgb: SIMD3<Float>) throws -> CVPixelBuffer {
        let attrs: [String: Any] = [kCVPixelBufferMetalCompatibilityKey as String: true,
                                    kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()]
        var pb: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                  attrs as CFDictionary, &pb) == kCVReturnSuccess, let pb else {
            throw MetalContext.MetalError.textureCreation("test camera buffer")
        }
        CVBufferSetAttachment(pb, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        let y = 0.2126 * rgb.x + 0.7152 * rgb.y + 0.0722 * rgb.z
        let cb = (rgb.z - y) / 1.8556 + 0.5
        let cr = (rgb.x - y) / 1.5748 + 0.5
        func q(_ v: Float) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        let yBase = CVPixelBufferGetBaseAddressOfPlane(pb, 0)!.assumingMemoryBound(to: UInt8.self)
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        for row in 0..<height { memset(yBase + row * yStride, Int32(q(y)), width) }
        let cBase = CVPixelBufferGetBaseAddressOfPlane(pb, 1)!.assumingMemoryBound(to: UInt8.self)
        let cStride = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)
        for row in 0..<(height / 2) {
            for col in 0..<(width / 2) {
                cBase[row * cStride + col * 2] = q(cb)
                cBase[row * cStride + col * 2 + 1] = q(cr)
            }
        }
        return pb
    }

    private func sharedTexture(_ format: MTLPixelFormat, w: Int? = nil, h: Int? = nil) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w ?? width, height: h ?? height, mipmapped: false)
        d.usage = [.shaderRead, .shaderWrite]
        d.storageMode = .shared
        guard let t = context.device.makeTexture(descriptor: d) else { throw MetalContext.MetalError.textureCreation("test") }
        return t
    }

    struct PrepareResult { let rgb: SIMD3<Float>; let matte: Float; let gpuMs: Double }

    /// Runs prepareForeground and reads the centre pixel.
    func runPrepare(rgb: SIMD3<Float>, uniforms: DEKAFrameUniforms, lut: MTLTexture? = nil) throws -> PrepareResult {
        let pb = try makeCameraBuffer(rgb: rgb)
        guard let yT = context.textureCache.texture(from: pb, plane: 0, format: .r8Unorm),
              let cT = context.textureCache.texture(from: pb, plane: 1, format: .rg8Unorm) else {
            throw MetalContext.MetalError.textureCreation("test planes")
        }
        let fg = try sharedTexture(.rgba32Float)
        let matte = try sharedTexture(.r32Float)
        var u = uniforms
        guard let cb = context.queue.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else {
            throw MetalContext.MetalError.noQueue
        }
        enc.setComputePipelineState(context.prepareForeground)
        enc.setTexture(yT.texture, index: 0)
        enc.setTexture(cT.texture, index: 1)
        enc.setTexture(context.dummyMask, index: 2)
        enc.setTexture(context.dummy2D, index: 3)
        enc.setTexture(lut ?? context.identityLUT, index: 4)
        enc.setTexture(fg, index: 5)
        enc.setTexture(matte, index: 6)
        enc.setBytes(&u, length: MemoryLayout<DEKAFrameUniforms>.stride, index: 0)
        context.dispatch(enc, pipeline: context.prepareForeground, width: width, height: height)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        if let e = cb.error { throw e }
        withExtendedLifetime(yT) {}; withExtendedLifetime(cT) {}

        var px = [Float](repeating: 0, count: 4)
        fg.getBytes(&px, bytesPerRow: width * 16, from: MTLRegionMake2D(width / 2, height / 2, 1, 1), mipmapLevel: 0)
        var m: Float = 0
        matte.getBytes(&m, bytesPerRow: width * 4, from: MTLRegionMake2D(width / 2, height / 2, 1, 1), mipmapLevel: 0)
        return PrepareResult(rgb: SIMD3(px[0], px[1], px[2]), matte: m, gpuMs: (cb.gpuEndTime - cb.gpuStartTime) * 1000)
    }

    /// Runs packNV12 on a solid master and returns the (Y, Cb, Cr) bytes written.
    func runPackNV12(rgb: SIMD3<Float>) throws -> (y: UInt8, cb: UInt8, cr: UInt8) {
        let master = try sharedTexture(.rgba8Unorm)
        let px: [UInt8] = (0..<(width * height)).flatMap { _ in
            [UInt8(rgb.x * 255), UInt8(rgb.y * 255), UInt8(rgb.z * 255), 255]
        }
        px.withUnsafeBytes { master.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                                            withBytes: $0.baseAddress!, bytesPerRow: width * 4) }
        let pool = try PixelBufferPool(width: width, height: height, pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                       minimumBuffers: 1, maximumBuffers: 2)
        guard let out = pool.makeBuffer(),
              let yT = context.textureCache.texture(from: out, plane: 0, format: .r8Unorm, writable: true),
              let cT = context.textureCache.texture(from: out, plane: 1, format: .rg8Unorm, writable: true),
              let cb = context.queue.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else {
            throw MetalContext.MetalError.textureCreation("nv12 test")
        }
        enc.setComputePipelineState(context.packNV12)
        enc.setTexture(master, index: 0)
        enc.setTexture(yT.texture, index: 1)
        enc.setTexture(cT.texture, index: 2)
        context.dispatch(enc, pipeline: context.packNV12, width: width / 2, height: height / 2)
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        if let e = cb.error { throw e }
        CVPixelBufferLockBaseAddress(out, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(out, .readOnly) }
        let yv = CVPixelBufferGetBaseAddressOfPlane(out, 0)!.assumingMemoryBound(to: UInt8.self)[0]
        let c = CVPixelBufferGetBaseAddressOfPlane(out, 1)!.assumingMemoryBound(to: UInt8.self)
        return (yv, c[0], c[1])
    }

    // MARK: Named checks (shared by SYSTEM CHECK and unit tests)

    /// Decode accuracy: RGB → NV12 → GPU → RGB round trip.
    func checkDecode() throws -> (pass: Bool, detail: String) {
        let probes: [SIMD3<Float>] = [SIMD3(0.5, 0.5, 0.5), SIMD3(0.8, 0.2, 0.1), SIMD3(0.1, 0.6, 0.9)]
        var worst: Float = 0
        var ms = 0.0
        for p in probes {
            let r = try runPrepare(rgb: p, uniforms: neutralUniforms())
            worst = max(worst, simd_reduce_max(simd_abs(r.rgb - p)))
            ms = r.gpuMs
        }
        return (worst < 0.03, String(format: "max error %.3f, %.2f ms", worst, ms))
    }

    /// GPU trilinear LUT vs CPU reference on off-lattice colours.
    func checkLUT(_ lut: CubeLUT) throws -> (pass: Bool, detail: String) {
        let tex = try LUTTextureFactory.makeTexture(device: context.device, lut: lut)
        var u = neutralUniforms()
        u.lutEnabled = 1
        u.lutSize = Float(lut.size)
        u.lutIntensity = 1
        u.lutDomainMin = lut.domainMin
        u.lutDomainMax = lut.domainMax
        let probes: [SIMD3<Float>] = [SIMD3(0.5, 0.5, 0.5), SIMD3(0.73, 0.31, 0.12), SIMD3(0.2, 0.55, 0.81)]
        var worst: Float = 0
        for p in probes {
            let noLUT = try runPrepare(rgb: p, uniforms: neutralUniforms())    // actual decoded input
            let gpu = try runPrepare(rgb: p, uniforms: u, lut: tex)
            let cpu = lut.sample(noLUT.rgb)
            worst = max(worst, simd_reduce_max(simd_abs(gpu.rgb - cpu)))
        }
        return (worst < 0.01, String(format: "%ld³, GPU vs CPU max error %.4f", lut.size, worst))
    }

    /// Keyer: key colour → matte ≈ 0, skin/red → matte ≈ 1.
    func checkChroma() throws -> (pass: Bool, detail: String) {
        var u = neutralUniforms()
        ChromaKeyEngine.apply(mode: .greenScreen, chroma: ChromaSettings(), to: &u)
        let g = RGBAColor.chromaGreen
        let green = try runPrepare(rgb: SIMD3(g.r, g.g, g.b), uniforms: u)
        let skin = try runPrepare(rgb: SIMD3(0.85, 0.62, 0.52), uniforms: u)
        let pass = green.matte < 0.05 && skin.matte > 0.95
        return (pass, String(format: "green matte %.3f, skin matte %.3f", green.matte, skin.matte))
    }

    /// Output packing: known RGB → expected video-range NV12 codes.
    func checkNV12() throws -> (pass: Bool, detail: String) {
        let white = try runPackNV12(rgb: SIMD3(1, 1, 1))
        let black = try runPackNV12(rgb: SIMD3(0, 0, 0))
        let pass = abs(Int(white.y) - 235) <= 1 && abs(Int(black.y) - 16) <= 1 && abs(Int(white.cb) - 128) <= 1
        return (pass, "white Y=\(white.y) black Y=\(black.y) Cb=\(white.cb)")
    }
}
