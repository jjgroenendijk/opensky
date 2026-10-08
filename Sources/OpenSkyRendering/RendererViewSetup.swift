// MTKView configuration and the timed frame commit, split from Renderer.swift
// (file-length limits).

import Metal
import MetalKit
import Synchronization

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

    /// Commits the frame's last command buffer. Commit feedback reports when the GPU
    /// started and finished each part, which feeds the GPU time in `frameStats`.
    func commitFrame() {
        let parts = earlyFrameParts ?? GPUFrameParts(count: 1)
        earlyFrameParts = nil
        commandQueue.commit([commandBuffer], options: commitOptions(adding: parts))
    }

    /// Commits the culling and shadow work, so the GPU runs it while the CPU encodes
    /// the scene pass, then reopens the command buffer on the same allocator.
    func commitEarlyFrameWork(allocator: MTL4CommandAllocator) {
        let parts = GPUFrameParts(count: 2)
        earlyFrameParts = parts
        commandBuffer.endCommandBuffer()
        commandQueue.commit([commandBuffer], options: commitOptions(adding: parts))
        commandBuffer.beginCommandBuffer(allocator: allocator)
    }

    /// A frame whose scene pass failed after its early commit still commits and
    /// signals, so the allocator is not reset while the GPU reads it.
    func finishFailedFrame(afterEarlyCommit committed: Bool) {
        guard committed else { return }
        commitFrame()
        commandQueue.signalEvent(endFrameEvent, value: UInt64(frameIndex))
        frameIndex += 1
    }

    private func commitOptions(adding parts: GPUFrameParts) -> MTL4CommitOptions {
        let options = MTL4CommitOptions()
        let spans = frameStats.gpuSpans
        let log = gpuFrameLog
        options.addFeedbackHandler { feedback in
            guard let busy = parts.add(start: feedback.gpuStartTime, end: feedback.gpuEndTime)
            else { return }
            spans.record(start: 0, end: busy)
            log?.record(start: 0, end: busy)
        }
        return options
    }
}

/// One frame's GPU busy time over its command buffers. The parts add up rather than
/// span first start to last end, so the GPU idle gap between them does not count.
nonisolated final class GPUFrameParts: Sendable {
    private let state: Mutex<(busy: CFTimeInterval, remaining: Int)>

    init(count: Int) {
        state = Mutex((0, count))
    }

    /// The frame's busy seconds once every part has reported, else nil.
    func add(start: CFTimeInterval, end: CFTimeInterval) -> CFTimeInterval? {
        state.withLock { value in
            value.busy += max(end - start, 0)
            value.remaining -= 1
            return value.remaining == 0 ? value.busy : nil
        }
    }
}
