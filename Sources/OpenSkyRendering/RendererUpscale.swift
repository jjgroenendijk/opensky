// Drives MetalFX temporal upscaling each frame: jitters the scene projection, writes
// motion vectors, runs the scaler, and copies its output into the frame target before
// the SWF and UI layers draw at full size. See docs/rendering/upscaling.md.

import Metal
import MetalFX
import OpenSkyShaderTypes
import simd

/// The renderer's upscaling state.
public struct UpscaleState {
    let resources: UpscaleResources
    public var renderScale = RenderScale.off
    public var upscaler = UpscalerKind.temporal
    /// Set when MetalFX refused the last scaler request; cleared by a new choice.
    var creationFailure: String?
    var targets: UpscaleTargets?
    var frame = 0
    var resetPending = true
    /// History resets since launch: scene swaps, camera cuts, and size changes.
    public internal(set) var historyResets = 0
    var previousViewProjection: float4x4?
    var previousView: float4x4?
    var previousModels: [MotionKey: float4x4] = [:]
    var previousBonePrepared: Set<ObjectIdentifier> = []
    var motionInstances: MTLBuffer?
    var motionInstanceCapacity = 0
    /// Off leaves moving objects with camera motion only, so a test can see the pass work.
    var objectMotionEnabled = true

    init(resources: UpscaleResources) {
        self.resources = resources
    }

    public var unavailableReason: String? {
        if let creationFailure {
            return creationFailure
        }
        return switch upscaler {
        case .temporal: resources.temporalUnavailableReason
        case .spatial: resources.spatialUnavailableReason
        }
    }

    /// The sizes of the last upscaled frame; nil while upscaling is off.
    public var sizes: (input: SIMD2<Int>, output: SIMD2<Int>)? {
        targets.map { ($0.inputSize, $0.outputSize) }
    }

    public var status: UpscaleStatus {
        UpscaleStatus(
            inputSize: targets?.inputSize, outputSize: targets?.outputSize,
            upscaler: upscaler, historyResets: historyResets, unavailableReason: unavailableReason
        )
    }
}

/// One instance of a moving draw group, so last frame's matrix can be found again.
struct MotionKey: Hashable {
    let mesh: ObjectIdentifier
    let instance: UInt32
}

/// What one upscaled frame needs after the scene pass.
struct UpscaleFrame {
    let targets: UpscaleTargets
    let jitter: SIMD2<Float>
    let jitteredViewProjection: float4x4
    let viewProjection: float4x4
    let reset: Bool
}

extension Renderer {
    /// A camera that moves farther than this in one frame cut, so its history is stale.
    static let upscaleCutDistance: Float = 1024
    /// A turn larger than this in one frame is a cut too (cosine of 60 degrees).
    static let upscaleCutCosine: Float = 0.5

    public var renderScale: RenderScale {
        get { upscale.renderScale }
        set {
            guard newValue != upscale.renderScale else { return }
            upscale.renderScale = newValue
            upscale.creationFailure = nil
            upscale.resetPending = true
        }
    }

    public var upscaler: UpscalerKind {
        get { upscale.upscaler }
        set {
            guard newValue != upscale.upscaler else { return }
            upscale.upscaler = newValue
            upscale.creationFailure = nil
            upscale.resetPending = true
        }
    }

    /// Drops the upscaler's history, so the next frame shows nothing from earlier ones.
    public func resetUpscaleHistory() {
        upscale.resetPending = true
    }

    /// Prepares this frame's targets and jitter; nil draws at full size.
    func beginUpscaleFrame(
        target: MTL4RenderPassDescriptor,
        projection: float4x4,
        view: float4x4
    ) -> UpscaleFrame? {
        guard
            upscale.renderScale.isOn, upscale.unavailableReason == nil,
            let color = target.colorAttachments[0].texture,
            let targets = upscaleTargets(output: SIMD2(color.width, color.height), color: color)
        else {
            releaseUpscaleTargets()
            return nil
        }
        // The spatial scaler has no history to fill, so it gets the plain projection.
        let jitter = targets.kind == .temporal ? RenderScale.jitter(frame: upscale.frame) : .zero
        upscale.frame += 1
        let jittered = RenderScale.jittered(projection, by: jitter, inputSize: targets.inputSize)
        let reset = upscale.resetPending || isCameraCut(view: view)
        if reset {
            upscale.historyResets += 1
        }
        return UpscaleFrame(
            targets: targets,
            jitter: jitter,
            jitteredViewProjection: jittered * view,
            viewProjection: projection * view,
            reset: reset
        )
    }

    /// The scene pass targets at the input size, cleared like the frame target.
    func upscaleSceneDescriptor(
        _ frame: UpscaleFrame,
        matching target: MTL4RenderPassDescriptor
    ) -> MTL4RenderPassDescriptor {
        let descriptor = MTL4RenderPassDescriptor()
        descriptor.colorAttachments[0].texture = frame.targets.color
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = target.colorAttachments[0].clearColor
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.depthAttachment.texture = frame.targets.depth
        descriptor.depthAttachment.loadAction = .clear
        descriptor.depthAttachment.clearDepth = target.depthAttachment.clearDepth
        descriptor.depthAttachment.storeAction = .store
        descriptor.stencilAttachment.texture = frame.targets.depth
        descriptor.stencilAttachment.loadAction = .clear
        descriptor.stencilAttachment.storeAction = .dontCare
        return descriptor
    }

    /// Ends the scene encoder, writes motion, upscales, and opens a full-size encoder on
    /// `target` with the upscaled frame drawn. Nil when an encoder cannot be made.
    func encodeUpscale(
        _ frame: UpscaleFrame,
        sceneDepth: MTLTexture,
        target: MTL4RenderPassDescriptor,
        state: ScenePassState,
        frameOffset: Int
    ) -> ScenePassState? {
        switch frame.targets.scaler {
        case let .temporal(scaler):
            state.encoder.endEncoding()
            let uniforms = writeMotionUniforms(frame, slot: state.slot)
            guard
                encodeCameraMotion(frame, sceneDepth: sceneDepth, uniforms: uniforms),
                encodeObjectMotion(frame, sceneDepth: sceneDepth, state: state, uniforms: uniforms)
            else { return nil }
            encodeScaler(scaler, frame: frame, sceneDepth: sceneDepth)
        case let .spatial(scaler):
            state.encoder.barrier(
                afterStages: .fragment, beforeQueueStages: Self.upscaleStages,
                visibilityOptions: .device
            )
            state.encoder.endEncoding()
            scaler.colorTexture = frame.targets.color
            scaler.outputTexture = frame.targets.output
            scaler.inputContentWidth = frame.targets.inputSize.x
            scaler.inputContentHeight = frame.targets.inputSize.y
            scaler.encode(commandBuffer: commandBuffer)
        }
        guard
            let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: Self.upscaleCompositeDescriptor(target)
            )
        else { return nil }
        encoder.label = "Upscale Composite"
        encoder.barrier(
            afterQueueStages: Self.upscaleStages, beforeStages: .fragment,
            visibilityOptions: .device
        )
        bindScenePassFrameArguments(encoder: encoder, frameOffset: frameOffset)
        argumentTable.setTexture(
            frame.targets.output.gpuResourceID, index: TextureIndex.diffuse.rawValue
        )
        encoder.setRenderPipelineState(upscale.resources.composite)
        encoder.setDepthStencilState(uiResources.depthState)
        encoder.setCullMode(.none)
        encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
        finishUpscaleFrame(frame)
        var next = ScenePassState(encoder: encoder, slot: state.slot, frustum: state.frustum)
        next.drawCursor = state.drawCursor
        next.instanceCursor = state.instanceCursor
        next.stats = state.stats
        return next
    }

    /// Every stage the scaler's own encoders may use.
    static let upscaleStages: MTLStages = [.vertex, .fragment, .dispatch, .blit, .machineLearning]

    private func encodeScaler(
        _ scaler: any MTL4FXTemporalScaler, frame: UpscaleFrame, sceneDepth: MTLTexture
    ) {
        let input = frame.targets.inputSize
        scaler.colorTexture = frame.targets.color
        scaler.depthTexture = sceneDepth
        scaler.motionTexture = frame.targets.motion
        scaler.outputTexture = frame.targets.output
        scaler.inputContentWidth = input.x
        scaler.inputContentHeight = input.y
        // Signs checked against native frames: the other choices lose 2 to 8 dB.
        scaler.jitterOffsetX = frame.jitter.x
        scaler.jitterOffsetY = frame.jitter.y
        scaler.motionVectorScaleX = Float(input.x)
        scaler.motionVectorScaleY = Float(input.y)
        scaler.isDepthReversed = false
        scaler.reset = frame.reset
        scaler.encode(commandBuffer: commandBuffer)
    }

    private func finishUpscaleFrame(_ frame: UpscaleFrame) {
        upscale.previousViewProjection = frame.viewProjection
        upscale.previousView = freeFlyCamera.viewMatrix()
        upscale.previousBonePrepared = frameBonePrepared
        upscale.resetPending = false
    }

    private static func upscaleCompositeDescriptor(
        _ target: MTL4RenderPassDescriptor
    ) -> MTL4RenderPassDescriptor {
        let descriptor = MTL4RenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target.colorAttachments[0].texture
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.depthAttachment.texture = target.depthAttachment.texture
        descriptor.depthAttachment.loadAction = .clear
        descriptor.depthAttachment.clearDepth = target.depthAttachment.clearDepth
        descriptor.depthAttachment.storeAction = .dontCare
        descriptor.stencilAttachment.texture = target.stencilAttachment.texture
        descriptor.stencilAttachment.loadAction = .clear
        descriptor.stencilAttachment.storeAction = .dontCare
        return descriptor
    }

    private func isCameraCut(view: float4x4) -> Bool {
        guard let previous = upscale.previousView else { return true }
        let now = view.inverse
        let before = previous.inverse
        let moved = simd_distance(now.columns.3, before.columns.3)
        let turned = simd_dot(
            simd_normalize(SIMD3(now.columns.2.x, now.columns.2.y, now.columns.2.z)),
            simd_normalize(SIMD3(before.columns.2.x, before.columns.2.y, before.columns.2.z))
        )
        return moved > Self.upscaleCutDistance || turned < Self.upscaleCutCosine
    }

    private func upscaleTargets(output: SIMD2<Int>, color: MTLTexture) -> UpscaleTargets? {
        let input = upscale.renderScale.inputSize(width: output.x, height: output.y)
        if
            let targets = upscale.targets, targets.inputSize == input,
            targets.outputSize == output, targets.color.pixelFormat == color.pixelFormat,
            targets.kind == upscale.upscaler
        {
            return targets
        }
        releaseUpscaleTargets()
        guard
            let targets = try? UpscaleTargets(
                input: input, output: output, colorFormat: color.pixelFormat,
                kind: upscale.upscaler, compiler: pipelineCache
            )
        else {
            upscale.creationFailure = "MetalFX refused a \(upscale.upscaler) scaler"
                + " for \(input.x) x \(input.y) to \(output.x) x \(output.y)"
            return nil
        }
        upscale.targets = targets
        upscale.resetPending = true
        residencySet.addAllocations(targets.allocations)
        residencySet.commit()
        return targets
    }

    private func releaseUpscaleTargets() {
        guard let old = upscale.targets else { return }
        upscale.targets = nil
        upscale.previousViewProjection = nil
        upscale.previousView = nil
        upscale.previousModels = [:]
        retireAllocations(old.allocations)
    }
}
