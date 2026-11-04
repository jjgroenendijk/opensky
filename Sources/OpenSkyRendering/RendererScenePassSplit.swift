// Splitting the scene pass: the encoder ends, attachments are copied, and a second
// encoder continues on the same targets. Water reads the depth copy and, for its
// screen-space reflections, the colour copy; refraction shapes read the colour copy.

import Metal

/// The attachment to copy, and where the renderer keeps the copy between frames.
struct ScenePassCopy {
    let source: MTLTexture
    let target: ReferenceWritableKeyPath<Renderer, MTLTexture?>
    let label: String
}

extension Renderer {
    /// Nil when the copy or the second encoder cannot be made; the frame is then dropped.
    func splitScenePass(
        descriptor: MTL4RenderPassDescriptor,
        state: ScenePassState,
        frameOffset: Int,
        copies: [ScenePassCopy]
    ) -> ScenePassState? {
        state.encoder.endEncoding()
        let targets = copies.compactMap {
            keptCopy(matching: $0.source, at: $0.target, label: $0.label)
        }
        guard
            let label = copies.first?.label, targets.count == copies.count,
            let blit = commandBuffer.makeComputeCommandEncoder()
        else { return nil }
        blit.label = "\(label)Copy"
        blit.barrier(afterQueueStages: .fragment, beforeStages: .blit, visibilityOptions: .device)
        for (copy, target) in zip(copies, targets) {
            blit.copy(sourceTexture: copy.source, destinationTexture: target)
        }
        blit.barrier(afterStages: .blit, beforeQueueStages: .fragment, visibilityOptions: .device)
        blit.endEncoding()
        guard
            let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: Self.continuingDescriptor(after: descriptor)
            )
        else { return nil }
        bindScenePassFrameArguments(encoder: encoder, frameOffset: frameOffset)
        encoder.label = label
        encoder.setTriangleFillMode(state.fillMode)
        var next = ScenePassState(encoder: encoder, slot: state.slot, frustum: state.frustum)
        next.fillMode = state.fillMode
        next.drawCursor = state.drawCursor
        next.instanceCursor = state.instanceCursor
        next.stats = state.stats
        return next
    }

    /// The kept copy when it still matches `source`, else a new one in the residency set.
    func keptCopy(
        matching source: MTLTexture,
        at path: ReferenceWritableKeyPath<Renderer, MTLTexture?>,
        label: String
    ) -> MTLTexture? {
        if
            let copy = self[keyPath: path], copy.width == source.width,
            copy.height == source.height, copy.pixelFormat == source.pixelFormat
        {
            return copy
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: source.pixelFormat, width: source.width, height: source.height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "\(label)Copy"
        if let old = self[keyPath: path] {
            residencySet.removeAllocation(old)
        }
        residencySet.addAllocation(texture)
        residencySet.commit()
        self[keyPath: path] = texture
        return texture
    }

    /// The same targets, loading the color and depth drawn so far and keeping both.
    static func continuingDescriptor(
        after descriptor: MTL4RenderPassDescriptor
    ) -> MTL4RenderPassDescriptor {
        let next = MTL4RenderPassDescriptor()
        next.colorAttachments[0].texture = descriptor.colorAttachments[0].texture
        next.colorAttachments[0].loadAction = .load
        next.colorAttachments[0].storeAction = .store
        next.depthAttachment.texture = descriptor.depthAttachment.texture
        next.depthAttachment.loadAction = .load
        next.depthAttachment.storeAction = .store
        next.stencilAttachment.texture = descriptor.stencilAttachment.texture
        next.stencilAttachment.loadAction = .clear
        next.stencilAttachment.storeAction = .dontCare
        next.stencilAttachment.clearStencil = 0
        return next
    }
}
