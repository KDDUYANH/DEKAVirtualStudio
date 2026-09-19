//
//  ChromaKeyEngine.swift
//  Keyer parameters → uniforms. The matte itself is computed per pixel in ChromaKey.h and
//  feathered by GPUBlur. Key detection happens on the UNGRADED camera signal so colour or
//  LUT changes during a show never break the key.
//

import Foundation
import simd

enum ChromaKeyEngine {

    static func apply(mode: KeyMode, chroma: ChromaSettings, to u: inout DEKAFrameUniforms) {
        switch mode {
        case .off: u.keyMode = Int32(DEKA_KEY_OFF)
        case .greenScreen: u.keyMode = Int32(DEKA_KEY_CHROMA)
        case .aiCutout: u.keyMode = Int32(DEKA_KEY_AI)
        }
        u.keyCbCr = cbcr(of: chroma.keyColor)
        u.keySimilarity = max(0.001, chroma.similarity)
        u.keySmoothness = max(0.001, chroma.smoothness)
        u.keySpill = max(0, chroma.spill)
        u.keyEdge = max(-1, min(1, chroma.edge))
        u.keyOpacity = max(0, min(1, chroma.opacity))
    }

    /// Same maths as rgbToCbCr709 in ShaderCommon.h (kept in sync by a unit test).
    static func cbcr(of c: RGBAColor) -> SIMD2<Float> {
        let y = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
        return SIMD2((c.b - y) / 1.8556, (c.r - y) / 1.5748)
    }

    /// Picks a key colour from an average of camera samples (eyedropper), returns sRGB.
    static func averageColor(samples: [SIMD3<Float>]) -> RGBAColor? {
        guard !samples.isEmpty else { return nil }
        let sum = samples.reduce(SIMD3<Float>.zero, +) / Float(samples.count)
        return RGBAColor(r: sum.x, g: sum.y, b: sum.z)
    }
}
