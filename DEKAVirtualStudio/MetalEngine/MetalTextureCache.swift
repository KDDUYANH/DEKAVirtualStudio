//
//  MetalTextureCache.swift
//  CVPixelBuffer ↔ MTLTexture without copying (IOSurface sharing via CVMetalTextureCache).
//

import Metal
import CoreVideo

/// Keeps the CVMetalTexture alive for as long as the MTLTexture is in use by the GPU.
struct PlaneTexture {
    let texture: MTLTexture
    let cvTexture: CVMetalTexture
}

final class MetalTextureCache {
    private let cache: CVMetalTextureCache

    init(device: MTLDevice) throws {
        var c: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &c)
        guard status == kCVReturnSuccess, let c else { throw MetalContext.MetalError.textureCreation("CVMetalTextureCache") }
        cache = c
    }

    /// - Parameters:
    ///   - plane: plane index for planar formats (0 = Y, 1 = CbCr), 0 for packed formats.
    ///   - writable: request shaderWrite usage (GPU writes into the pixel buffer).
    func texture(from pixelBuffer: CVPixelBuffer, plane: Int, format: MTLPixelFormat, writable: Bool = false) -> PlaneTexture? {
        let planar = CVPixelBufferIsPlanar(pixelBuffer)
        let width = planar ? CVPixelBufferGetWidthOfPlane(pixelBuffer, plane) : CVPixelBufferGetWidth(pixelBuffer)
        let height = planar ? CVPixelBufferGetHeightOfPlane(pixelBuffer, plane) : CVPixelBufferGetHeight(pixelBuffer)
        var attrs: CFDictionary? = nil
        if writable {
            let usage: MTLTextureUsage = [.shaderRead, .shaderWrite]
            attrs = [kCVMetalTextureUsage as String: NSNumber(value: usage.rawValue)] as CFDictionary
        }
        var cvTex: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, pixelBuffer, attrs,
                                                               format, width, height, plane, &cvTex)
        guard status == kCVReturnSuccess, let cvTex, let tex = CVMetalTextureGetTexture(cvTex) else { return nil }
        return PlaneTexture(texture: tex, cvTexture: cvTex)
    }

    /// Call occasionally (e.g. on memory warning) to release unused IOSurface mappings.
    func flush() { CVMetalTextureCacheFlush(cache, 0) }
}
