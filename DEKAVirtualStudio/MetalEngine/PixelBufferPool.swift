//
//  PixelBufferPool.swift
//  IOSurface-backed, Metal-compatible buffers. The GPU writes the program straight into these,
//  and the same buffer goes to VideoToolbox (via WebRTC) and AVAssetWriter — no copies.
//

import CoreVideo
import Foundation

final class PixelBufferPool {
    let width: Int
    let height: Int
    let pixelFormat: OSType
    private let pool: CVPixelBufferPool
    private let auxAttributes: CFDictionary

    init(width: Int, height: Int, pixelFormat: OSType, minimumBuffers: Int = 6, maximumBuffers: Int = 12) throws {
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        let poolAttrs: [String: Any] = [kCVPixelBufferPoolMinimumBufferCountKey as String: minimumBuffers]
        let pbAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ]
        var p: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttrs as CFDictionary, pbAttrs as CFDictionary, &p)
        guard status == kCVReturnSuccess, let p else {
            throw NSError(domain: "DEKA.PixelBufferPool", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Pixel buffer pool creation failed (\(status))"])
        }
        pool = p
        // Upper bound: if downstream (encoder) holds too many buffers we drop instead of growing memory.
        auxAttributes = [kCVPixelBufferPoolAllocationThresholdKey as String: maximumBuffers] as CFDictionary
    }

    /// Returns nil when the pool is exhausted (downstream is behind) — caller drops the frame.
    func makeBuffer() -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pool, auxAttributes, &pb)
        guard status == kCVReturnSuccess, let pb else { return nil }
        if pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
            // Tag colour so encoders/players interpret it correctly (BT.709, video range).
            CVBufferSetAttachment(pb, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
            CVBufferSetAttachment(pb, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_ITU_R_709_2, .shouldPropagate)
            CVBufferSetAttachment(pb, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)
        }
        return pb
    }

    func flush() { CVPixelBufferPoolFlush(pool, [.excessBuffers]) }
}
