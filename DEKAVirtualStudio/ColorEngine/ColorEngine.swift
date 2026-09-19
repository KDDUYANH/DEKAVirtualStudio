//
//  ColorEngine.swift
//  Maps operator-facing ColorSettings to GPU uniforms. All pixel work is in ColorGrade.h.
//

import Foundation
import CoreVideo
import simd

enum ColorEngine {

    /// Writes the colour section of the frame uniforms.
    static func apply(_ s: ColorSettings, to u: inout DEKAFrameUniforms) {
        u.colorEnabled = s.enabled ? 1 : 0
        u.exposure = s.exposure
        u.contrast = s.contrast
        u.highlights = s.highlights
        u.shadows = s.shadows
        u.whites = s.whites
        u.blacks = s.blacks
        u.saturation = s.saturation
        u.vibrance = s.vibrance
        u.hueRadians = s.hue * .pi / 180
        u.midtoneDetail = s.midtoneDetail
        u.wbGains = whiteBalanceGains(temperature: s.temperature, tint: s.tint)
        u.lift = s.lift.simd + SIMD3(repeating: s.liftMaster)
        u.gammaRGB = s.gamma.simd * s.gammaMaster
        u.gain = s.gain.simd * s.gainMaster
        u.offset = s.offset.simd + SIMD3(repeating: s.offsetMaster)
    }

    /// Creative temperature/tint as linear-light RGB gains, normalised so luminance is unchanged
    /// (moving WB never changes exposure).
    static func whiteBalanceGains(temperature: Float, tint: Float) -> SIMD3<Float> {
        let t = max(-1, min(1, temperature))
        let m = max(-1, min(1, tint))
        var g = SIMD3<Float>(1 + 0.30 * t, 1 - 0.20 * m, 1 - 0.30 * t)
        g = simd_max(g, SIMD3(repeating: 0.05))
        let luma = simd_dot(g, SIMD3<Float>(0.2126, 0.7152, 0.0722))
        return g / luma
    }

    // MARK: Input decode

    struct YCbCrDecode: Equatable {
        var matrix: simd_float3x3
        var offset: SIMD3<Float>
        var scale: SIMD3<Float>
    }

    /// Chooses the decode matrix from the buffer's own attachments (BT.601 / 709 / 2020) and range.
    static func decode(for pixelBuffer: CVPixelBuffer) -> YCbCrDecode {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let fullRange = (format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        var matrixName: String = kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String
        if let m = CVBufferCopyAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, nil) as? String {
            matrixName = m
        }
        return decode(matrixName: matrixName, fullRange: fullRange)
    }

    static func decode(matrixName: String, fullRange: Bool) -> YCbCrDecode {
        // Columns are the coefficients of Y, Cb, Cr.
        let kr: Float, kb: Float
        if matrixName == (kCVImageBufferYCbCrMatrix_ITU_R_601_4 as String) {
            kr = 0.299; kb = 0.114
        } else if matrixName == (kCVImageBufferYCbCrMatrix_ITU_R_2020 as String) {
            kr = 0.2627; kb = 0.0593
        } else {
            kr = 0.2126; kb = 0.0722
        }
        let kg = 1 - kr - kb
        let crR = 2 * (1 - kr)
        let cbB = 2 * (1 - kb)
        let cbG = -cbB * kb / kg
        let crG = -crR * kr / kg
        let m = simd_float3x3(columns: (SIMD3<Float>(1, 1, 1),
                                        SIMD3<Float>(0, cbG, cbB),
                                        SIMD3<Float>(crR, crG, 0)))
        if fullRange {
            return YCbCrDecode(matrix: m, offset: SIMD3(0, 0.5, 0.5), scale: SIMD3(1, 1, 1))
        }
        return YCbCrDecode(matrix: m,
                           offset: SIMD3(16.0 / 255.0, 128.0 / 255.0, 128.0 / 255.0),
                           scale: SIMD3(255.0 / 219.0, 255.0 / 224.0, 255.0 / 224.0))
    }
}
