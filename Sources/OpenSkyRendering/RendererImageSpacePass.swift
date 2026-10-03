// The image-space composite: the scene encoder ends after world geometry, the
// color target is copied to a scratch texture, and a second encoder draws one
// fullscreen triangle that grades the copy back over the target. The overlay,
// SWF, and UI layers then draw ungraded on top. See docs/rendering/image-space.md.

import Metal
import MetalKit
import OpenSkyShaderTypes
import simd

/// The composite pipeline, its uniform ring, and the scratch copy of the scene color.
public final class ImageSpacePassResources {
    public let pipeline: MTLRenderPipelineState
    public let uniformBuffer: MTLBuffer
    /// Sized to the last target; replaced when the target size or format changes.
    public private(set) var sceneCopy: MTLTexture?

    static let uniformStride = (MemoryLayout<ImageSpaceUniforms>.size + 0xFF) & -0x100

    init(device: MTLDevice, library: MTLLibrary, pixelFormat: MTLPixelFormat) throws {
        let compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())
        let vertex = MTL4LibraryFunctionDescriptor()
        vertex.library = library
        vertex.name = "skyVertex"
        let fragment = MTL4LibraryFunctionDescriptor()
        fragment.library = library
        fragment.name = "imageSpaceFragment"
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = "ImageSpaceComposite"
        descriptor.vertexFunctionDescriptor = vertex
        descriptor.fragmentFunctionDescriptor = fragment
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        pipeline = try compiler.makeRenderPipelineState(descriptor: descriptor)
        guard
            let buffer = device.makeBuffer(
                length: Self.uniformStride * Renderer.maxFramesInFlight,
                options: .storageModeShared
            )
        else { throw RendererError.bufferAllocationFailed }
        buffer.label = "ImageSpaceUniforms"
        uniformBuffer = buffer
    }

    /// A copy target matching `target`, made resident in `residency` when it is new.
    func copyTarget(matching target: MTLTexture, residency: MTLResidencySet) -> MTLTexture? {
        if
            let sceneCopy, sceneCopy.width == target.width, sceneCopy.height == target.height,
            sceneCopy.pixelFormat == target.pixelFormat
        {
            return sceneCopy
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: target.pixelFormat,
            width: target.width,
            height: target.height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .private
        guard let texture = target.device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "ImageSpaceSceneCopy"
        if let sceneCopy {
            residency.removeAllocation(sceneCopy)
        }
        residency.addAllocation(texture)
        residency.commit()
        sceneCopy = texture
        return texture
    }
}

extension Renderer {
    /// The values this frame grades with, or nil when the pass is off or would change
    /// nothing. A graded frame stores depth, so the second encoder can load it.
    func prepareImageSpacePass(descriptor: MTL4RenderPassDescriptor) -> ImageSpaceParameters? {
        let parameters = imageSpace.current.clampedForDisplay
        guard
            imageSpace.passEnabled, !parameters.isNeutral,
            descriptor.colorAttachments[0].texture != nil
        else { return nil }
        descriptor.depthAttachment.storeAction = .store
        return parameters
    }

    /// Ends the scene encoder, copies its color, and opens the second encoder with the
    /// composite drawn. Nil when an encoder cannot be made; the frame is then dropped.
    func encodeImageSpacePass(
        _ parameters: ImageSpaceParameters,
        descriptor: MTL4RenderPassDescriptor,
        state: ScenePassState,
        frameOffset: Int
    ) -> ScenePassState? {
        state.encoder.endEncoding()
        guard
            let target = descriptor.colorAttachments[0].texture,
            let copy = imageSpacePass.copyTarget(matching: target, residency: residencySet),
            let blit = commandBuffer.makeComputeCommandEncoder()
        else { return nil }
        blit.label = "ImageSpaceCopy"
        blit.barrier(afterQueueStages: .fragment, beforeStages: .blit, visibilityOptions: .device)
        blit.copy(sourceTexture: target, destinationTexture: copy)
        blit.barrier(afterStages: .blit, beforeQueueStages: .fragment, visibilityOptions: .device)
        blit.endEncoding()
        guard
            let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: Self.compositeDescriptor(after: descriptor)
            )
        else { return nil }
        bindScenePassFrameArguments(encoder: encoder, frameOffset: frameOffset)
        encoder.label = "Image Space Composite"
        var uniforms = Self.uniforms(parameters, targetHeight: target.height)
        let offset = ImageSpacePassResources.uniformStride * state.slot
        imageSpacePass.uniformBuffer.contents().advanced(by: offset)
            .copyMemory(from: &uniforms, byteCount: MemoryLayout<ImageSpaceUniforms>.size)
        argumentTable.setAddress(
            imageSpacePass.uniformBuffer.gpuAddress + UInt64(offset),
            index: BufferIndex.imageSpaceUniforms.rawValue
        )
        argumentTable.setTexture(copy.gpuResourceID, index: TextureIndex.sceneColor.rawValue)
        encoder.setRenderPipelineState(imageSpacePass.pipeline)
        encoder.setCullMode(.none)
        encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
        var next = ScenePassState(encoder: encoder, slot: state.slot, frustum: state.frustum)
        next.drawCursor = state.drawCursor
        next.instanceCursor = state.instanceCursor
        next.stats = state.stats
        return next
    }

    /// The same targets, loading the graded color and the stored depth.
    private static func compositeDescriptor(
        after descriptor: MTL4RenderPassDescriptor
    ) -> MTL4RenderPassDescriptor {
        let next = MTL4RenderPassDescriptor()
        next.colorAttachments[0].texture = descriptor.colorAttachments[0].texture
        next.colorAttachments[0].loadAction = .load
        next.colorAttachments[0].storeAction = .store
        next.depthAttachment.texture = descriptor.depthAttachment.texture
        next.depthAttachment.loadAction = .load
        next.depthAttachment.storeAction = .dontCare
        next.stencilAttachment.texture = descriptor.stencilAttachment.texture
        next.stencilAttachment.loadAction = .clear
        next.stencilAttachment.storeAction = .dontCare
        next.stencilAttachment.clearStencil = 0
        return next
    }

    /// The blur radius is authored for a 1080-pixel-high frame and scales with the target.
    static func uniforms(
        _ parameters: ImageSpaceParameters,
        targetHeight: Int
    ) -> ImageSpaceUniforms {
        ImageSpaceUniforms(
            tint: parameters.tint,
            fade: parameters.fade,
            grading: SIMD4(
                parameters.saturation,
                parameters.brightness,
                parameters.contrast,
                parameters.blurRadius * Float(targetHeight) / 1080
            ),
            extra: SIMD4(parameters.doubleVision, 0, 0, 0)
        )
    }
}
