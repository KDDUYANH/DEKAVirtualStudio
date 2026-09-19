//
//  GPUBlur.swift
//  Separable Gaussian on the GPU. Weights are cached per radius (computed once).
//  Large radii are run at reduced resolution (the result is visually identical and ~16× cheaper).
//

import Metal

final class GPUBlur {
    private let context: MetalContext
    private var weightCache: [Int: MTLBuffer] = [:]
    private let lock = Locked(0)

    static let maxRadius = 32

    init(context: MetalContext) { self.context = context }

    private func weights(radius: Int) -> MTLBuffer? {
        lock.mutate { (_: inout Int) -> MTLBuffer? in
            if let b = weightCache[radius] { return b }
            let sigma = max(Float(radius) / 2.5, 0.5)
            var w = (0...radius).map { i in exp(-Float(i * i) / (2 * sigma * sigma)) }
            let total = w[0] + 2 * w.dropFirst().reduce(0, +)
            w = w.map { $0 / total }
            let buffer = context.device.makeBuffer(bytes: w, length: w.count * MemoryLayout<Float>.stride, options: .storageModeShared)
            weightCache[radius] = buffer
            return buffer
        }
    }

    /// src → (tmp) → dst, all the same size. radius 0 = no-op (caller should bind src directly).
    func encode(_ cb: MTLCommandBuffer, source: MTLTexture, temp: MTLTexture, destination: MTLTexture, radius: Int) {
        let r = min(max(radius, 1), Self.maxRadius)
        guard let w = weights(radius: r), let enc = cb.makeComputeCommandEncoder() else { return }
        enc.label = "GaussianBlur r\(r)"
        enc.setComputePipelineState(context.gaussianBlur)
        enc.setBuffer(w, offset: 0, index: 1)

        var p = DEKABlurParams(radius: Int32(r), horizontal: 1)
        enc.setTexture(source, index: 0)
        enc.setTexture(temp, index: 1)
        enc.setBytes(&p, length: MemoryLayout<DEKABlurParams>.stride, index: 0)
        context.dispatch(enc, pipeline: context.gaussianBlur, width: temp.width, height: temp.height)

        p.horizontal = 0
        enc.setTexture(temp, index: 0)
        enc.setTexture(destination, index: 1)
        enc.setBytes(&p, length: MemoryLayout<DEKABlurParams>.stride, index: 0)
        context.dispatch(enc, pipeline: context.gaussianBlur, width: destination.width, height: destination.height)
        enc.endEncoding()
    }

    func resample(_ cb: MTLCommandBuffer, source: MTLTexture, destination: MTLTexture) {
        guard let enc = cb.makeComputeCommandEncoder() else { return }
        enc.label = "Resample"
        enc.setComputePipelineState(context.resample)
        enc.setTexture(source, index: 0)
        enc.setTexture(destination, index: 1)
        context.dispatch(enc, pipeline: context.resample, width: destination.width, height: destination.height)
        enc.endEncoding()
    }
}
