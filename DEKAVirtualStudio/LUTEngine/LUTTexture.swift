//
//  LUTTexture.swift
//  Uploads a CubeLUT into a 3D texture (x = red, y = green, z = blue, matching .cube order),
//  sampled with hardware trilinear filtering in LUT.h.
//

import Metal
import simd

enum LUTTextureFactory {

    static func makeTexture(device: MTLDevice, lut: CubeLUT) throws -> MTLTexture {
        let n = lut.size
        let d = MTLTextureDescriptor()
        d.textureType = .type3D
        d.width = n; d.height = n; d.depth = n
        d.usage = [.shaderRead]
        d.storageMode = .shared
        #if arch(arm64)
        d.pixelFormat = .rgba16Float
        var texels = [Float16](repeating: 1, count: n * n * n * 4)
        for (i, v) in lut.values.enumerated() {
            texels[i * 4 + 0] = Float16(v.x)
            texels[i * 4 + 1] = Float16(v.y)
            texels[i * 4 + 2] = Float16(v.z)
        }
        let bytesPerTexel = 8
        #else
        d.pixelFormat = .rgba32Float
        var texels = [Float](repeating: 1, count: n * n * n * 4)
        for (i, v) in lut.values.enumerated() {
            texels[i * 4 + 0] = v.x; texels[i * 4 + 1] = v.y; texels[i * 4 + 2] = v.z
        }
        let bytesPerTexel = 16
        #endif
        guard let tex = device.makeTexture(descriptor: d) else {
            throw MetalContext.MetalError.textureCreation("LUT \(lut.title)")
        }
        texels.withUnsafeBytes { raw in
            tex.replace(region: MTLRegionMake3D(0, 0, 0, n, n, n), mipmapLevel: 0, slice: 0,
                        withBytes: raw.baseAddress!, bytesPerRow: n * bytesPerTexel, bytesPerImage: n * n * bytesPerTexel)
        }
        tex.label = "LUT \(lut.title) \(n)³"
        return tex
    }

    static func makeIdentity(device: MTLDevice, size: Int) throws -> MTLTexture {
        try makeTexture(device: device, lut: .identity(size: size))
    }
}

/// GPU-ready LUT: texture + the uniforms the shader needs.
struct LoadedLUT {
    let id: String
    let lut: CubeLUT
    let texture: MTLTexture
}
