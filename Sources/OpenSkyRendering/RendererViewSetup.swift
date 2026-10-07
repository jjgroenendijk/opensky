// MTKView configuration and the timed frame commit, split from Renderer.swift
// (file-length limits).

import Metal
import MetalKit

extension Renderer {
    public static func configure(view: MTKView) {
        view.colorPixelFormat = .bgra8Unorm_srgb
        // Depth plus stencil: SWF clip masks need a stencil attachment; the 3D passes
        // ignore it.
        view.depthStencilPixelFormat = .depth32Float_stencil8
        // Depth lives only inside the scene pass, so it stays in tile memory.
        view.depthStencilStorageMode = .memoryless
        view.sampleCount = 1
        // The image-space pass copies the drawable's color, which needs a non-framebuffer-only
        // texture.
        view.framebufferOnly = false
    }

    /// Commits the frame's command buffer. Commit feedback reports when the GPU
    /// started and finished the whole frame, which feeds the GPU time in `frameStats`.
    func commitFrame() {
        let options = MTL4CommitOptions()
        let spans = frameStats.gpuSpans
        let log = gpuFrameLog
        options.addFeedbackHandler { feedback in
            spans.record(start: feedback.gpuStartTime, end: feedback.gpuEndTime)
            log?.record(start: feedback.gpuStartTime, end: feedback.gpuEndTime)
        }
        commandQueue.commit([commandBuffer], options: options)
    }
}
