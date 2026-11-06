// The image-space composite. Most grades read only their own pixel, so one fullscreen
// triangle grades the color in tile memory inside the scene encoder. A grade with blur
// or double vision reads neighbor pixels: the scene encoder then ends, the color is
// copied to a scratch texture, and a second encoder grades the copy back over the
// target. The overlay, SWF, and UI layers then draw ungraded on top. See
// docs/rendering/image-space.md.

import Metal
import MetalKit
import OpenSkyRenderCore
import OpenSkyRenderResources
import OpenSkyShaderTypes
import QuartzCore
import simd

/// The composite pipelines, their uniform ring, and the scratch targets of the split pass.
public final class ImageSpacePassResources {
    public let pipeline: MTLRenderPipelineState
    /// Grades the pixel in tile memory, so the scene pass needs no copy and no stored depth.
    public let tilePipeline: MTLRenderPipelineState
    public let uniformBuffer: MTLBuffer
    /// The `PostEffectUniforms` per frame slot.
    public let postUniformBuffer: MTLBuffer
    /// The tone-mapping luminance sum and sample count per frame slot.
    public let luminanceBuffer: MTLBuffer
    /// Sized to the last target; replaced when the target size or format changes.
    public private(set) var sceneCopy: MTLTexture?
    /// The depth the split pass stores between its two encoders. The scene depth is
    /// memoryless, so it cannot outlive one encoder.
    public private(set) var storedDepth: MTLTexture?
    /// Last frame's view-projection, for the motion blur.
    var previousViewProjection: float4x4?

    static let uniformStride = (MemoryLayout<ImageSpaceUniforms>.size + 0xFF) & -0x100
    static let postUniformStride = (MemoryLayout<PostEffectUniforms>.size + 0xFF) & -0x100

    init(
        device: MTLDevice,
        library: MTLLibrary,
        compiler: PipelineCache,
        pixelFormat: MTLPixelFormat
    ) throws {
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
                length: Self.uniformStride * GPUFactory.maxFramesInFlight,
                options: .storageModeShared
            )
        else { throw RendererError.bufferAllocationFailed }
        buffer.label = "ImageSpaceUniforms"
        uniformBuffer = buffer
        guard
            let post = device.makeBuffer(
                length: Self.postUniformStride * GPUFactory.maxFramesInFlight,
                options: .storageModeShared
            )
        else { throw RendererError.bufferAllocationFailed }
        post.label = "PostEffectUniforms"
        postUniformBuffer = post
        guard
            let luminance = device.makeBuffer(
                length: Self.luminanceStride * GPUFactory.maxFramesInFlight,
                options: .storageModeShared
            )
        else { throw RendererError.bufferAllocationFailed }
        luminance.label = "ImageSpaceLuminance"
        luminance.contents().initializeMemory(
            as: UInt8.self, repeating: 0, count: luminance.length
        )
        luminanceBuffer = luminance
    }

    static let luminanceStride = 2 * MemoryLayout<UInt32>.stride

    /// The slot's luminance from the frame that last used it, cleared for this frame.
    func takeMeanLuminance(slot: Int) -> Float? {
        let values = luminanceBuffer.contents().advanced(by: Self.luminanceStride * slot)
            .bindMemory(to: UInt32.self, capacity: 2)
        defer {
            values[0] = 0
            values[1] = 0
        }
        return ToneMappingState.meanLuminance(sum: values[0], count: values[1])
    }

    private static func makePipeline(
        compiler: PipelineCache,
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
    /// The screen-space effects; nil when none is on.
    let post: PostEffectUniforms?
    /// Blur, double vision, and the screen-space effects sample other pixels, which
    /// tile memory cannot reach.
    let splitsPass: Bool

    init(uniforms: ImageSpaceUniforms, post: PostEffectUniforms? = nil, alwaysSplits: Bool) {
        self.uniforms = uniforms
        self.post = post
        splitsPass = alwaysSplits || post != nil || uniforms.grading.w > 0.5
            || uniforms.extra.x > 0 || uniforms.extra.y > 0 || uniforms.radialBlur.x > 0
            || uniforms.bloom.z > 0
    }
}

extension Renderer {
    /// The grade this frame draws, or nil when the pass is off or would change nothing.
    func imageSpaceGrade(descriptor: MTL4RenderPassDescriptor, slot: Int) -> ImageSpaceGrade? {
        let parameters = frameInput.imageSpace
            .current(withScreenFade: effects.loadingCover == nil).clampedForDisplay
        let toneMaps = frameInput.imageSpace.passEnabled && frameInput.imageSpace.toneMapping
            .enabled
            && ToneMappingState.isActive(parameters.hdr)
        let measured = imageSpacePass.takeMeanLuminance(slot: slot)
        let deltaTime = eyeAdaptationClock.advance(to: CACurrentMediaTime(), paused: false)
        if toneMaps, let measured {
            eyeAdaptation.advance(
                measured: measured, speed: parameters.hdr.eyeAdaptSpeed, deltaTime: deltaTime
            )
        } else if !toneMaps {
            eyeAdaptation.reset()
        }
        guard let target = descriptor.colorAttachments[0].texture else { return nil }
        let post = postEffectUniforms(parameters, targetHeight: target.height)
        let viewProjection = sceneProjection * frameInput.view.viewMatrix()
        let previous = imageSpacePass.previousViewProjection ?? viewProjection
        imageSpacePass.previousViewProjection = viewProjection
        let blooms = target.pixelFormat == .rgba16Float && parameters.hdr.bloomScale > 0
        let grades = frameInput.imageSpace.passEnabled
            && (toneMaps || blooms || !parameters.isNeutral)
        guard grades || post != nil else { return nil }
        let toneMapping = toneMaps
            ? SIMD4(
                eyeAdaptation.exposure(strength: parameters.hdr.eyeAdaptStrength),
                parameters.hdr.white, parameters.hdr.eyeAdaptStrength > 0 ? 1 : 0, 0
            )
            : SIMD4(1, 0, 0, 0)
        return ImageSpaceGrade(
            uniforms: Self.uniforms(
                grades ? parameters : .neutral, targetHeight: target.height,
                toneMapping: toneMapping,
                motion: ImageSpaceMotion(
                    blooms: grades && blooms,
                    reprojection: previous * viewProjection.inverse
                )
            ),
            post: post,
            alwaysSplits: imageSpaceAlwaysSplits
        )
    }

    /// The descriptor the scene pass begins with, and its depth recorded for the readout.
    /// A split grade or a water depth read moves depth and stencil to a stored target,
    /// because the second encoder loads the depth the first one wrote.
    func scenePassDescriptor(
        _ descriptor: MTL4RenderPassDescriptor,
        grade: ImageSpaceGrade?,
        storesDepth: Bool = false
    ) -> MTL4RenderPassDescriptor? {
        lastSceneDepth = descriptor.depthAttachment.texture.map {
            RenderTargetEntry(texture: $0, name: "Scene depth")
        }
        return splitPassDescriptor(descriptor, splits: grade?.splitsPass == true || storesDepth)
    }

    private func splitPassDescriptor(
        _ descriptor: MTL4RenderPassDescriptor,
        splits: Bool
    ) -> MTL4RenderPassDescriptor? {
        guard splits else { return descriptor }
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
        markScenePassSegment(next: .imageSpace)
        guard
            let target = descriptor.colorAttachments[0].texture,
            let copy = imageSpacePass.copyTarget(matching: target, residency: residencySet),
            let depthCopy = postEffectDepthCopy(grade, descriptor: descriptor),
            let blit = commandBuffer.makeComputeCommandEncoder()
        else { return nil }
        blit.label = "ImageSpaceCopy"
        blit.barrier(afterQueueStages: .fragment, beforeStages: .blit, visibilityOptions: .device)
        blit.copy(sourceTexture: target, destinationTexture: copy)
        if let depth = descriptor.depthAttachment.texture, let destination = depthCopy.copy {
            blit.copy(sourceTexture: depth, destinationTexture: destination)
            argumentTable.setTexture(
                destination.gpuResourceID, index: TextureIndex.sceneDepth.rawValue
            )
        }
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
        argumentTable.setAddress(
            imageSpacePass.luminanceBuffer.gpuAddress
                + UInt64(ImageSpacePassResources.luminanceStride * slot),
            index: BufferIndex.imageSpaceLuminance.rawValue
        )
        var post = grade.post ?? PostEffectUniforms()
        let postOffset = ImageSpacePassResources.postUniformStride * slot
        imageSpacePass.postUniformBuffer.contents().advanced(by: postOffset)
            .copyMemory(from: &post, byteCount: MemoryLayout<PostEffectUniforms>.size)
        argumentTable.setAddress(
            imageSpacePass.postUniformBuffer.gpuAddress + UInt64(postOffset),
            index: BufferIndex.postEffectUniforms.rawValue
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

    /// The blur and bloom radii are authored for a 1080-pixel-high frame and scale with
    /// the target.
    static func uniforms(
        _ parameters: ImageSpaceParameters,
        targetHeight: Int,
        toneMapping: SIMD4<Float> = SIMD4(1, 0, 0, 0),
        motion: ImageSpaceMotion = ImageSpaceMotion()
    ) -> ImageSpaceUniforms {
        let pixels = Float(targetHeight) / 1080
        let radial = parameters.radialBlur
        let hdr = parameters.hdr
        return ImageSpaceUniforms(
            tint: parameters.tint,
            fade: parameters.fade,
            grading: SIMD4(
                parameters.saturation,
                parameters.brightness,
                parameters.contrast,
                parameters.blurRadius * pixels
            ),
            extra: SIMD4(
                lowHalf: SIMD2(parameters.doubleVision, parameters.motionBlur),
                highHalf: radial.center
            ),
            toneMapping: toneMapping,
            radialBlur: SIMD4(radial.strength, radial.rampUp, radial.start, radial.rampDown),
            radialBlurEnd: SIMD4(radial.downStart, 0, 0, 0),
            bloom: motion.blooms
                ? SIMD4(
                    hdr.bloomBlurRadius * ImageSpaceMotion.bloomPixelsPerRadius * pixels,
                    hdr.bloomThreshold, hdr.bloomScale, hdr.receiveBloomThreshold
                )
                : .zero,
            reprojection: motion.reprojection
        )
    }
}

/// The per-frame inputs of the grade that the image-space values do not hold.
struct ImageSpaceMotion {
    /// The `IMGS` bloom radius runs 1 to 7 (CK wiki); one step is this many pixels at 1080.
    static let bloomPixelsPerRadius: Float = 4
    var blooms = false
    /// Last frame's view-projection times the inverse of this one's.
    var reprojection = matrix_identity_float4x4
}
