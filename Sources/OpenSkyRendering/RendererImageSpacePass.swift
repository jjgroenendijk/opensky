// The image-space composite. Most grades read only their own pixel, so one fullscreen
// triangle grades the color in tile memory inside the scene encoder. A grade with blur
// or double vision reads neighbor pixels: the scene encoder then ends, the color is
// copied to a scratch texture, and a second encoder grades the copy back over the
// target. The overlay, SWF, and UI layers then draw ungraded on top. See
// docs/rendering/image-space.md.

import Metal
import MetalKit
import OpenSkyShaderTypes
import simd

/// The composite pipelines, their uniform ring, and the scratch targets of the split pass.
public final class ImageSpacePassResources {
    public let pipeline: MTLRenderPipelineState
    /// Grades the pixel in tile memory, so the scene pass needs no copy and no stored depth.
    public let tilePipeline: MTLRenderPipelineState
    public let uniformBuffer: MTLBuffer
    /// Sized to the last target; replaced when the target size or format changes.
    public private(set) var sceneCopy: MTLTexture?
    /// The depth the split pass stores between its two encoders. The scene depth is
    /// memoryless, so it cannot outlive one encoder.
    public private(set) var storedDepth: MTLTexture?

    static let uniformStride = (MemoryLayout<ImageSpaceUniforms>.size + 0xFF) & -0x100

    init(device: MTLDevice, library: MTLLibrary, pixelFormat: MTLPixelFormat) throws {
        let compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())
        pipeline = try Self.makePipeline(
            compiler: compiler, library: library, pixelFormat: pixelFormat,
            fragment: "imageSpaceFragment"
        )
        tilePipeline = try Self.makePipeline(
            compiler: compiler, library: library, pixelFormat: pixelFormat,
            fragment: "imageSpaceTileFragment"
        )
        guard
            let buffer = device.makeBuffer(
                length: Self.uniformStride * Renderer.maxFramesInFlight,
                options: .storageModeShared
            )
        else { throw RendererError.bufferAllocationFailed }
        buffer.label = "ImageSpaceUniforms"
        uniformBuffer = buffer
    }

    private static func makePipeline(
        compiler: MTL4Compiler,
        library: MTLLibrary,
        pixelFormat: MTLPixelFormat,
        fragment: String
    ) throws -> MTLRenderPipelineState {
        let vertex = MTL4LibraryFunctionDescriptor()
        vertex.library = library
        vertex.name = "skyVertex"
        let fragmentFunction = MTL4LibraryFunctionDescriptor()
        fragmentFunction.library = library
        fragmentFunction.name = fragment
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = "ImageSpaceComposite"
        descriptor.vertexFunctionDescriptor = vertex
        descriptor.fragmentFunctionDescriptor = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        return try compiler.makeRenderPipelineState(descriptor: descriptor)
    }

    /// A copy target matching `target`, made resident in `residency` when it is new.
    func copyTarget(matching target: MTLTexture, residency: MTLResidencySet) -> MTLTexture? {
        if let sceneCopy, Self.matches(sceneCopy, target, format: target.pixelFormat) {
            return sceneCopy
        }
        let texture = Self.makeTarget(
            matching: target, format: target.pixelFormat, usage: .shaderRead,
            label: "ImageSpaceSceneCopy"
        )
        sceneCopy = Self.replace(sceneCopy, with: texture, residency: residency)
        return texture
    }

    /// A stored depth-stencil target the size of `target`, made resident when it is new.
    func depthTarget(matching target: MTLTexture, residency: MTLResidencySet) -> MTLTexture? {
        let format = MTLPixelFormat.depth32Float_stencil8
        if let storedDepth, Self.matches(storedDepth, target, format: format) {
            return storedDepth
        }
        let texture = Self.makeTarget(
            matching: target, format: format, usage: .renderTarget,
            label: "ImageSpaceStoredDepth"
        )
        storedDepth = Self.replace(storedDepth, with: texture, residency: residency)
        return texture
    }

    private static func matches(_ texture: MTLTexture, _ target: MTLTexture, format: MTLPixelFormat)
        -> Bool
    {
        texture.width == target.width && texture.height == target.height
            && texture.pixelFormat == format
    }

    private static func makeTarget(
        matching target: MTLTexture,
        format: MTLPixelFormat,
        usage: MTLTextureUsage,
        label: String
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format, width: target.width, height: target.height, mipmapped: false
        )
        descriptor.usage = usage
        descriptor.storageMode = .private
        let texture = target.device.makeTexture(descriptor: descriptor)
        texture?.label = label
        return texture
    }

    private static func replace(
        _ old: MTLTexture?,
        with new: MTLTexture?,
        residency: MTLResidencySet
    ) -> MTLTexture? {
        guard let new else { return old }
        if let old {
            residency.removeAllocation(old)
        }
        residency.addAllocation(new)
        residency.commit()
        return new
    }
}

/// The grade one frame draws.
struct ImageSpaceGrade {
    let uniforms: ImageSpaceUniforms
    /// Blur and double vision sample other pixels, which tile memory cannot reach.
    let splitsPass: Bool

    init(uniforms: ImageSpaceUniforms, alwaysSplits: Bool) {
        self.uniforms = uniforms
        splitsPass = alwaysSplits || uniforms.grading.w > 0.5 || uniforms.extra.x > 0
    }
}

extension Renderer {
    /// The grade this frame draws, or nil when the pass is off or would change nothing.
    func imageSpaceGrade(descriptor: MTL4RenderPassDescriptor) -> ImageSpaceGrade? {
        let parameters = imageSpace.current.clampedForDisplay
        guard
            imageSpace.passEnabled, !parameters.isNeutral,
            let target = descriptor.colorAttachments[0].texture
        else { return nil }
        return ImageSpaceGrade(
            uniforms: Self.uniforms(parameters, targetHeight: target.height),
            alwaysSplits: imageSpaceAlwaysSplits
        )
    }

    /// The descriptor the scene pass begins with, and its depth recorded for the readout.
    /// A split grade moves depth and stencil to a stored target, because the second
    /// encoder loads the depth the first one wrote.
    func scenePassDescriptor(
        _ descriptor: MTL4RenderPassDescriptor,
        grade: ImageSpaceGrade?
    ) -> MTL4RenderPassDescriptor? {
        lastSceneDepth = descriptor.depthAttachment.texture.map {
            RenderTargetEntry(texture: $0, name: "Scene depth")
        }
        return splitPassDescriptor(descriptor, grade: grade)
    }

    private func splitPassDescriptor(
        _ descriptor: MTL4RenderPassDescriptor,
        grade: ImageSpaceGrade?
    ) -> MTL4RenderPassDescriptor? {
        guard grade?.splitsPass == true else { return descriptor }
        guard
            let target = descriptor.colorAttachments[0].texture,
            let depth = imageSpacePass.depthTarget(matching: target, residency: residencySet)
        else { return nil }
        let split = MTL4RenderPassDescriptor()
        split.colorAttachments[0].texture = target
        split.colorAttachments[0].loadAction = descriptor.colorAttachments[0].loadAction
        split.colorAttachments[0].storeAction = .store
        split.colorAttachments[0].clearColor = descriptor.colorAttachments[0].clearColor
        split.depthAttachment.texture = depth
        split.depthAttachment.loadAction = .clear
        split.depthAttachment.storeAction = .store
        split.depthAttachment.clearDepth = descriptor.depthAttachment.clearDepth
        split.stencilAttachment.texture = depth
        split.stencilAttachment.loadAction = .clear
        split.stencilAttachment.storeAction = .dontCare
        split.stencilAttachment.clearStencil = 0
        return split
    }

    /// Draws the grade and restores the scene depth state. False when the split pass
    /// cannot open its second encoder; the frame is then dropped.
    func encodeImageSpaceGrade(
        _ grade: ImageSpaceGrade,
        descriptor: MTL4RenderPassDescriptor,
        state: inout ScenePassState,
        frameOffset: Int
    ) -> Bool {
        if grade.splitsPass {
            guard
                let graded = encodeImageSpacePass(
                    grade, descriptor: descriptor, state: state, frameOffset: frameOffset
                )
            else { return false }
            state = graded
        } else {
            encodeImageSpaceTile(grade, state: state)
        }
        state.encoder.setDepthStencilState(depthState)
        return true
    }

    /// Grades the frame inside the scene encoder: one fullscreen triangle reads each pixel
    /// from tile memory and writes the graded color back.
    func encodeImageSpaceTile(_ grade: ImageSpaceGrade, state: ScenePassState) {
        bindImageSpaceUniforms(grade, slot: state.slot)
        state.encoder.setRenderPipelineState(imageSpacePass.tilePipeline)
        state.encoder.setDepthStencilState(uiResources.depthState)
        state.encoder.setCullMode(.none)
        state.encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
    }

    /// Ends the scene encoder, copies its color, and opens the second encoder with the
    /// composite drawn. Nil when an encoder cannot be made; the frame is then dropped.
    func encodeImageSpacePass(
        _ grade: ImageSpaceGrade,
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
        bindImageSpaceUniforms(grade, slot: state.slot)
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

    private func bindImageSpaceUniforms(_ grade: ImageSpaceGrade, slot: Int) {
        var uniforms = grade.uniforms
        let offset = ImageSpacePassResources.uniformStride * slot
        imageSpacePass.uniformBuffer.contents().advanced(by: offset)
            .copyMemory(from: &uniforms, byteCount: MemoryLayout<ImageSpaceUniforms>.size)
        argumentTable.setAddress(
            imageSpacePass.uniformBuffer.gpuAddress + UInt64(offset),
            index: BufferIndex.imageSpaceUniforms.rawValue
        )
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
