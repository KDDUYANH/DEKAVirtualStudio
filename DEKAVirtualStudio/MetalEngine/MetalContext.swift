//
//  MetalContext.swift
//  One device, one queue, one library, all pipeline states compiled once at launch.
//

import Metal
import CoreVideo

final class MetalContext {

    enum MetalError: LocalizedError {
        case noDevice, noQueue, noLibrary, missingFunction(String), textureCreation(String)
        var errorDescription: String? {
            switch self {
            case .noDevice: return "This device has no Metal GPU."
            case .noQueue: return "Could not create a Metal command queue."
            case .noLibrary: return "Metal shader library missing from the app bundle."
            case .missingFunction(let n): return "Metal function \(n) not found."
            case .textureCreation(let n): return "Could not create texture \(n)."
            }
        }
    }

    let device: MTLDevice
    let queue: MTLCommandQueue
    let library: MTLLibrary
    let textureCache: MetalTextureCache

    let prepareForeground: MTLComputePipelineState
    let compositeProgram: MTLComputePipelineState
    let mixPrograms: MTLComputePipelineState
    let gaussianBlur: MTLComputePipelineState
    let resample: MTLComputePipelineState
    let packNV12: MTLComputePipelineState
    let preview: MTLRenderPipelineState

    /// 1×1 / 2³ placeholders so every shader slot is always bound.
    let dummy2D: MTLTexture
    let dummyMask: MTLTexture
    let identityLUT: MTLTexture

    static let previewPixelFormat: MTLPixelFormat = .bgra8Unorm

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw MetalError.noDevice }
        guard let queue = device.makeCommandQueue() else { throw MetalError.noQueue }
        queue.label = "DTEK.master"
        guard let library = device.makeDefaultLibrary() else { throw MetalError.noLibrary }
        self.device = device
        self.queue = queue
        self.library = library
        self.textureCache = try MetalTextureCache(device: device)

        func compute(_ name: String) throws -> MTLComputePipelineState {
            guard let fn = library.makeFunction(name: name) else { throw MetalError.missingFunction(name) }
            return try device.makeComputePipelineState(function: fn)
        }
        prepareForeground = try compute("prepareForeground")
        compositeProgram = try compute("compositeProgram")
        mixPrograms = try compute("mixPrograms")
        gaussianBlur = try compute("gaussianBlur")
        resample = try compute("resampleTexture")
        packNV12 = try compute("packNV12")

        let rp = MTLRenderPipelineDescriptor()
        guard let v = library.makeFunction(name: "previewVertex") else { throw MetalError.missingFunction("previewVertex") }
        guard let f = library.makeFunction(name: "previewFragment") else { throw MetalError.missingFunction("previewFragment") }
        rp.vertexFunction = v
        rp.fragmentFunction = f
        rp.colorAttachments[0].pixelFormat = Self.previewPixelFormat
        preview = try device.makeRenderPipelineState(descriptor: rp)

        dummy2D = try Self.makeSolid2D(device: device, value: [0, 0, 0, 0], format: .rgba8Unorm, name: "dummy2D")
        dummyMask = try Self.makeSolid2D(device: device, value: [255, 255, 255, 255], format: .rgba8Unorm, name: "dummyMask")
        identityLUT = try LUTTextureFactory.makeIdentity(device: device, size: 2)
    }

    // MARK: Texture helpers

    func makeTexture(width: Int, height: Int, format: MTLPixelFormat, label: String,
                     usage: MTLTextureUsage = [.shaderRead, .shaderWrite]) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
        d.usage = usage
        d.storageMode = .private
        guard let t = device.makeTexture(descriptor: d) else { throw MetalError.textureCreation(label) }
        t.label = label
        return t
    }

    private static func makeSolid2D(device: MTLDevice, value: [UInt8], format: MTLPixelFormat, name: String) throws -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: 1, height: 1, mipmapped: false)
        d.usage = [.shaderRead]
        d.storageMode = .shared
        guard let t = device.makeTexture(descriptor: d) else { throw MetalError.textureCreation(name) }
        value.withUnsafeBytes { raw in
            t.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: raw.baseAddress!, bytesPerRow: 4)
        }
        t.label = name
        return t
    }

    /// Threadgroup sizing for a 2D compute grid.
    func dispatch(_ encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, width: Int, height: Int) {
        let w = pipeline.threadExecutionWidth
        let h = max(1, pipeline.maxTotalThreadsPerThreadgroup / w)
        let tg = MTLSize(width: w, height: h, depth: 1)
        if device.supportsFamily(.apple4) {
            // Non-uniform threadgroups: exact grid, no wasted threads (A11+).
            encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1), threadsPerThreadgroup: tg)
        } else {
            let groups = MTLSize(width: (width + w - 1) / w, height: (height + h - 1) / h, depth: 1)
            encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: tg)
        }
    }
}
