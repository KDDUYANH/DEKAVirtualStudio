//
//  MetalRenderer.swift
//  The on-screen monitor. A CAMetalLayer-backed UIView whose drawable is filled INSIDE the
//  master command buffer on the video queue — the preview costs one extra draw, never a
//  CPU copy, never a main-thread hop. (MTKView is a wrapper over the same CAMetalLayer; we
//  drive the layer directly so rendering stays on the capture thread.)
//

import UIKit
import Metal
import QuartzCore

final class PreviewMetalView: UIView {

    override class var layerClass: AnyClass { CAMetalLayer.self }
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    /// drawableSize as seen by the render thread.
    fileprivate let drawableSize = Locked(CGSize.zero)

    func attach(device: MTLDevice) {
        metalLayer.device = device
        metalLayer.pixelFormat = MetalContext.previewPixelFormat
        metalLayer.framebufferOnly = true
        metalLayer.maximumDrawableCount = 3
        metalLayer.contentsGravity = .resizeAspect
        metalLayer.isOpaque = true
        backgroundColor = .black
        isOpaque = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.nativeScale ?? UIScreen.main.nativeScale
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        metalLayer.drawableSize = size
        drawableSize.set(size)
    }
}

/// Encodes the monitor draw. Held by the compositor; the view is attached/detached by the UI.
final class MetalRenderer {
    private let context: MetalContext
    /// Captured on the main thread at attach time; UIView.layer must not be touched off-main.
    private struct Target { let layer: CAMetalLayer; let size: Locked<CGSize> }
    private let target = Locked<Target?>(nil)

    private let pendingPresents = Locked(0)
    var previewMode = Locked<Int32>(Int32(DEKA_PREVIEW_PROGRAM))

    init(context: MetalContext) { self.context = context }

    /// Main thread only.
    func attach(_ view: PreviewMetalView?) {
        guard let view else { target.set(nil); return }
        view.attach(device: context.device)
        target.set(Target(layer: view.metalLayer, size: view.drawableSize))
    }

    /// Called on the render thread with the master command buffer.
    func encode(into commandBuffer: MTLCommandBuffer,
                program: MTLTexture, matte: MTLTexture, yPlane: MTLTexture, cPlane: MTLTexture,
                uniforms: inout DEKAFrameUniforms) {
        guard let target = target.get() else { return }
        let size = target.size.get()
        guard size.width > 0, size.height > 0 else { return }
        // nextDrawable() blocks when all drawables are queued. Never let the monitor stall the
        // program: skip the monitor frame if two presents are still pending.
        guard pendingPresents.get() < 2 else { return }
        guard let drawable = target.layer.nextDrawable() else { return }
        pendingPresents.mutate { $0 += 1 }
        // Completion always fires (even on GPU error), so the counter can never get stuck.
        commandBuffer.addCompletedHandler { [pendingPresents] _ in pendingPresents.mutate { $0 = max(0, $0 - 1) } }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.label = "Preview"

        // Aspect-fit the program into the view.
        let programAspect = Float(program.width) / Float(max(program.height, 1))
        let viewAspect = Float(size.width / size.height)
        var p = DEKAPreviewUniforms()
        p.scale = viewAspect > programAspect ? SIMD2(programAspect / viewAspect, 1) : SIMD2(1, viewAspect / programAspect)
        p.mode = previewMode.get()

        enc.setRenderPipelineState(context.preview)
        enc.setVertexBytes(&p, length: MemoryLayout<DEKAPreviewUniforms>.stride, index: 0)
        enc.setFragmentTexture(program, index: 0)
        enc.setFragmentTexture(matte, index: 1)
        enc.setFragmentTexture(yPlane, index: 2)
        enc.setFragmentTexture(cPlane, index: 3)
        enc.setFragmentBytes(&p, length: MemoryLayout<DEKAPreviewUniforms>.stride, index: 0)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<DEKAFrameUniforms>.stride, index: 1)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
        commandBuffer.present(drawable)
    }
}
