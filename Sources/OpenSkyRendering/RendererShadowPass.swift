// Sun-shadow depth pre-pass, split from RendererScenePass.swift. It fits
// orthographic cascades to the camera frustum (ShadowCascadeMath) and renders the
// casters that intersect each cascade into one shadow-array slice. Water, sky,
// and LOD do not cast. Dedicated shadow rings keep it apart from the scene pass.

import Foundation
import Metal
import OpenSkyFormatsCore
import OpenSkyShaderTypes
import simd

/// Sun-shadow quality tier. Drives cascade count, shadow range, and
/// PCF tap count; the app sidebar selects it. `.off` renders no shadow pass
/// (equivalent to `sunShadowsEnabled = false`, but a persisted user choice).
nonisolated public enum ShadowQuality: String, CaseIterable, Sendable {
    case off
    case low
    case high
}

/// Per-frame shadow-pass culling + draw accounting, mirror of SceneDrawStats:
/// deterministic evidence for the per-cascade caster-culling tests and budget
/// triage. Counts are summed across every rendered cascade.
nonisolated public struct ShadowDrawStats: Equatable, Sendable {
    /// drawIndexedPrimitives calls encoded (all cascades).
    public var drawCalls = 0
    /// Caster instances drawn after per-cascade frustum culling (static +
    /// terrain), summed across cascades.
    public var drawnInstances = 0
    /// (instance, cascade) pairs the frustum test skipped this frame.
    public var culledInstances = 0
    /// Cascade slices actually rendered (2 low, 3 high).
    public var cascadesRendered = 0

    public mutating func formMaximum(_ other: ShadowDrawStats) {
        drawCalls = max(drawCalls, other.drawCalls)
        drawnInstances = max(drawnInstances, other.drawnInstances)
        culledInstances = max(culledInstances, other.culledInstances)
        cascadesRendered = max(cascadesRendered, other.cascadesRendered)
    }

    public init(
        drawCalls: Int = 0,
        drawnInstances: Int = 0,
        culledInstances: Int = 0,
        cascadesRendered: Int = 0
    ) {
        self.drawCalls = drawCalls
        self.drawnInstances = drawnInstances
        self.culledInstances = culledInstances
        self.cascadesRendered = cascadesRendered
    }
}

extension Renderer {
    /// Per-cascade encode context: the open depth encoder plus the cascade's
    /// transform, caster-culling frustum, and this frame's ring slot.
    private struct ShadowCascadeContext {
        let cascade: ShadowCascade
        let frustum: Frustum
        let encoder: MTL4RenderCommandEncoder
        /// The cull view: 0 is the camera, so cascade `i` is `1 + i`.
        let cullView: Int
    }

    /// Running cursors + stats threaded through one frame's cascade encodes.
    /// `base` is this frame slot's shadow instance-ring origin; `instanceCursor`
    /// advances as each cascade appends its surviving-caster run.
    private struct ShadowPassState {
        let slot: Int
        let base: Int
        var instanceCursor = 0
        var drawCursor = 0
        var stats = ShadowDrawStats()
    }

    // MARK: - Quality parameters

    /// Shadows render this frame only when both the dev toggle and a non-off
    /// quality allow it — `H` flips the toggle without losing the quality.
    public var shadowRenders: Bool {
        sunShadowsEnabled && shadowQuality != .off
    }

    /// Cascades to render: 2 for low (cheaper), 3 for high. The shadow map
    /// keeps all ShadowConstantCascadeCount slices allocated either way; low
    /// simply renders fewer and the shader pads the unused splits.
    public var shadowCascadeCount: Int {
        shadowQuality == .low ? 2 : ShadowConstant.cascadeCount.rawValue
    }

    /// Sun-shadow far bound for the active quality.
    public var activeShadowDistance: Float {
        shadowQuality == .low ? Self.shadowDistanceLow : Self.shadowDistance
    }

    /// PCF kernel radius bound into FrameUniforms: 0 -> single compare tap
    /// (low), 1 -> the 3x3 kernel (high). Read by sunShadowFactor.
    public var shadowSampleRadius: UInt32 {
        shadowQuality == .low ? 0 : 1
    }

    /// Shadow instance-ring slots one frame slot can need: every scene
    /// instance drawn in every cascade (per-cascade contiguous runs).
    public var shadowInstanceSlotCapacity: Int {
        ShadowConstant.cascadeCount.rawValue * instanceSlotCapacity
    }

    // MARK: - Cascade uniforms (consumed by the scene pass)

    /// Direction the sun travels (sun -> scene), matching the scene pass's
    /// FrameUniforms.sunDirection source.
    private var sunTravelDirection: SIMD3<Float> {
        scene.lighting?.directionalDirection ?? camera.sunDirection
    }

    /// This frame's cascade `index` world->light-clip matrix for FrameUniforms;
    /// identity pads slots past the produced cascade count.
    public func shadowCascadeMatrix(_ index: Int) -> float4x4 {
        index < shadowCascades.count ? shadowCascades[index].viewProjection
            : matrix_identity_float4x4
    }

    /// Per-cascade far bounds packed for the shader, padded with the last real
    /// bound (mirrors ShadowCascadeMath.cascadeIndex padding).
    public func shadowCascadeSplitBounds() -> SIMD4<Float> {
        let lastFar = shadowCascades.last?.splitFar ?? Self.shadowDistance
        func far(_ index: Int) -> Float {
            index < shadowCascades.count ? shadowCascades[index].splitFar : lastFar
        }
        return SIMD4(far(0), far(1), far(2), lastFar)
    }

    /// Recovers the vertical fov + aspect the projection was built with — the
    /// cascades must fit the exact frustum the scene pass renders. Valid for
    /// MatrixMath.perspective (ys = 1/tan(fov/2), xs = ys/aspect).
    private static func fovAspect(from projection: float4x4) -> (fovY: Float, aspect: Float) {
        let ys = projection.columns.1.y
        let xs = projection.columns.0.x
        let fovY = ys > .ulpOfOne ? 2 * atanf(1 / ys) : MatrixMath.radians(fromDegrees: 65)
        let aspect = xs > .ulpOfOne ? ys / xs : 1
        return (fovY, aspect)
    }

    // MARK: - Pass encode

    /// Encodes the whole shadow pre-pass onto the open command buffer. Returns
    /// false only when a cascade encoder cannot be created (caller aborts the
    /// frame); an idle pass (shadows off / no casters) returns true having
    /// reset the per-frame shadow state so the scene pass shades unshadowed.
    /// Records its own CPU wall time in `lastShadowUpdateMS` every frame.
    public func encodeShadowPass(slot: Int, projection: float4x4) -> Bool {
        let started = DispatchTime.now().uptimeNanoseconds
        defer {
            lastShadowUpdateMS =
                Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        }
        // First encode step of the frame -> owns the shared per-frame reset.
        frameBonePrepared.removeAll(keepingCapacity: true)
        frameMorphPrepared.removeAll(keepingCapacity: true)
        shadowCascades = []
        shadowsActiveThisFrame = false
        lastShadowDrawStats = ShadowDrawStats()

        let cascades = frameCascades(projection: projection)
        // The cull runs here, before any pass draws, for the camera and each cascade.
        encodeGPUCulling(
            slot: slot,
            viewProjections: [projection * freeFlyCamera.viewMatrix()]
                + cascades.map(\.viewProjection)
        )
        guard !cascades.isEmpty else { return true }

        var state = ShadowPassState(slot: slot, base: slot * shadowInstanceSlotCapacity)
        guard encodeCascades(cascades, state: &state) else { return false }
        lastShadowDrawStats = state.stats
        shadowCascades = cascades
        shadowsActiveThisFrame = true
        return true
    }

    /// This frame's cascades; empty when shadows are off or nothing casts.
    private func frameCascades(projection: float4x4) -> [ShadowCascade] {
        guard shadowRenders else { return [] }
        let hasCasters = shadowOpaqueDrawGroups.contains(where: \.castsShadows)
            || shadowAlphaTestedDrawGroups.contains(where: \.castsShadows)
            || !scene.terrain.isEmpty
        guard hasCasters else { return [] }
        let (fovY, aspect) = Self.fovAspect(from: projection)
        return ShadowCascadeMath.makeCascades(ShadowCascadeRequest(
            cameraToWorld: freeFlyCamera.viewMatrix().inverse,
            fovYRadians: fovY,
            aspectRatio: aspect,
            nearPlane: Self.nearPlane,
            shadowDistance: activeShadowDistance,
            sunDirection: sunTravelDirection,
            cascadeCount: shadowCascadeCount,
            lambda: Self.shadowSplitLambda,
            shadowMapResolution: ShadowConstant.mapResolution.rawValue,
            casterBackup: Self.shadowCasterBackup,
            residentBounds: residentCasterBounds()
        ))
    }

    /// One depth encoder per cascade; each renders the frustum-surviving
    /// casters into its array slice. Returns false if an encoder is unavailable.
    private func encodeCascades(
        _ cascades: [ShadowCascade],
        state: inout ShadowPassState
    ) -> Bool {
        for (index, cascade) in cascades.enumerated() {
            guard let encoder = makeShadowEncoder(cascade: index) else { return false }
            encoder.label = "Shadow Cascade \(index)"
            encoder.setArgumentTable(argumentTable, stages: [.vertex, .fragment])
            encoder.setDepthStencilState(depthState)
            encoder.setFrontFacing(.counterClockwise)
            encoder.setDepthBias(Self.shadowDepthBias, slopeScale: Self.shadowSlopeScale, clamp: 0)
            argumentTable.setSamplerState(
                sampler.gpuResourceID,
                index: SamplerIndex.trilinear.rawValue
            )
            let context = ShadowCascadeContext(
                cascade: cascade,
                frustum: Frustum(viewProjection: cascade.viewProjection),
                encoder: encoder,
                cullView: 1 + index
            )
            // The shadow lists, not the camera lists: a first-person player
            // is hidden from the eye and still casts (RendererPlayerBody).
            encodeCasterGroups(
                shadowOpaqueDrawGroups, list: .opaque, in: context, state: &state
            )
            encodeCasterGroups(
                shadowAlphaTestedDrawGroups, list: .alphaTested, in: context, state: &state
            )
            encodeShadowTerrain(in: context, state: &state)
            // MTL4 does not auto-track cross-encoder hazards: without a barrier
            // the scene pass may sample the shadow map before these depth
            // writes land (intermittent whole-frame shadow corruption). One
            // producer barrier on the last cascade covers every prior cascade
            // encoder ("current and prior encoders"), so the scene pass's
            // fragment sampling waits for all shadow depth writes.
            if index == cascades.count - 1 {
                encoder.barrier(
                    afterStages: .fragment,
                    beforeQueueStages: .fragment,
                    visibilityOptions: .device
                )
            }
            encoder.endEncoding()
            state.stats.cascadesRendered += 1
        }
        return true
    }

    /// World-AABB union of every resident caster (opaque + alphaTested +
    /// terrain), used to clamp each cascade's caster backup. Only movable casters
    /// merge here; the rest was built with the scene. nil when any caster is
    /// unbounded (conservative: no clamp).
    private func residentCasterBounds() -> ModelBounds? {
        guard !shadowCasters.isUnbounded else { return nil }
        var result = shadowCasters.fixed
        for instance in shadowCasters.movable {
            guard let bounds = drawn(instance).bounds else { return nil }
            result = result.map { $0.union(bounds) } ?? bounds
        }
        return result
    }

    // MARK: - Caster culling + draw

    /// Per group: cull per instance against this cascade's frustum, append the
    /// survivors' transforms into the shadow instance ring, draw once with the
    /// surviving instanceCount. Pipeline switches lazily on caster kind.
    private func encodeCasterGroups(
        _ groups: [DrawGroup],
        list: GPUCullList,
        in context: ShadowCascadeContext,
        state: inout ShadowPassState
    ) {
        let alphaTested = list == .alphaTested
        var boundPipeline: ObjectIdentifier?
        // The same mask the scene pass uses. Hiding the statics while their
        // shadows still fell on the terrain would make the tool actively
        // misleading — the frame would show a shadow with no caster.
        let layers = effectiveRenderLayers
        for (index, group) in groups.enumerated()
            where group.castsShadows && layers.contains(group.layer)
        {
            guard
                let visible = visibleCasters(
                    of: group, at: index, list: list, in: context, state: &state
                )
            else { continue }
            let pipeline = shadowPipeline(group: group, alphaTested: alphaTested)
            if boundPipeline != ObjectIdentifier(pipeline) {
                context.encoder.setRenderPipelineState(pipeline)
                boundPipeline = ObjectIdentifier(pipeline)
            }
            drawCasterGroup(
                group,
                alphaTested: alphaTested,
                visible: visible,
                in: context,
                state: &state
            )
        }
    }

    /// The group's surviving casters for this cascade, or nil when none survive.
    private func visibleCasters(
        of group: DrawGroup,
        at index: Int,
        list: GPUCullList,
        in context: ShadowCascadeContext,
        state: inout ShadowPassState
    ) -> VisibleInstances? {
        switch gpuVisibility(
            of: index, in: list, view: context.cullView, slot: state.slot,
            frustum: context.frustum
        ) {
        case .skipped:
            return nil
        case let .drawn(visible):
            return visible
        case .cpu:
            let run = writeVisibleShadowInstances(of: group, in: context, state: &state)
            guard run.written > 0 else { return nil }
            return .packed(
                count: run.written,
                address: shadowInstanceBuffer.gpuAddress + UInt64(run.byteOffset)
            )
        }
    }

    /// Writes the group's frustum-surviving instance transforms tightly packed
    /// from the running shadow instance cursor; returns the survivor count and
    /// the byte offset its draw binds the ring at. Total written per frame slot
    /// <= cascadeCount x scene.instanceCount <= ring capacity.
    private func writeVisibleShadowInstances(
        of group: DrawGroup,
        in context: ShadowCascadeContext,
        state: inout ShadowPassState
    ) -> (written: Int, byteOffset: Int) {
        let stride = MemoryLayout<InstanceTransform>.stride
        let base = state.base + state.instanceCursor
        var written = 0
        for placed in group.instances {
            // Same substitution the scene pass makes, so a moving body's shadow
            // travels with it (RendererDynamicPose.swift).
            let instance = drawn(placed)
            if let bounds = instance.bounds, !context.frustum.intersects(bounds) {
                state.stats.culledInstances += 1
                continue
            }
            var transform = InstanceTransform(
                modelMatrix: instance.modelMatrix,
                normalMatrix: instance.normalMatrix,
                instanceColor: SIMD4(1, 1, 1, 1),
                grassParameters: .zero
            )
            shadowInstanceBuffer.contents()
                .advanced(by: (base + written) * stride)
                .copyMemory(from: &transform, byteCount: MemoryLayout<InstanceTransform>.size)
            written += 1
        }
        state.instanceCursor += written
        state.stats.drawnInstances += written
        return (written, base * stride)
    }

    /// Binds the group's buffers/textures and emits one instanced draw for the
    /// surviving casters of this cascade.
    private func drawCasterGroup(
        _ group: DrawGroup,
        alphaTested: Bool,
        visible: VisibleInstances,
        in context: ShadowCascadeContext,
        state: inout ShadowPassState
    ) {
        let uniformOffset = writeShadowDrawUniforms(
            slot: state.slot,
            draw: state.drawCursor,
            lightViewProjection: context.cascade.viewProjection,
            modelMatrix: matrix_identity_float4x4,
            material: group.material
        )
        state.drawCursor += 1
        state.stats.drawCalls += 1
        argumentTable.setAddress(
            group.mesh.vertexBuffer.gpuAddress,
            index: BufferIndex.vertices.rawValue
        )
        argumentTable.setAddress(
            shadowDrawUniformBuffer.gpuAddress + UInt64(uniformOffset),
            index: BufferIndex.drawUniforms.rawValue
        )
        argumentTable.setAddress(
            visible.address,
            index: BufferIndex.instanceTransforms.rawValue
        )
        if group.mesh.isSkinned {
            bindShadowSkinning(for: group.mesh, slot: state.slot)
        }
        bindShadowMorph(group.faceMorph, slot: state.slot)
        if alphaTested {
            argumentTable.setTexture(
                streamedBinding(group.material.diffuse),
                index: TextureIndex.diffuse.rawValue
            )
        }
        context.encoder.setCullMode(group.material.doubleSided ? .none : .back)
        context.encoder.drawInstances(of: group.mesh, visible)
    }

    private func encodeShadowTerrain(
        in context: ShadowCascadeContext,
        state: inout ShadowPassState
    ) {
        guard effectiveRenderLayers.contains(.terrain) else { return }
        let encoder = context.encoder
        var pipelineBound = false
        for item in scene.terrain {
            if let bounds = item.bounds, !context.frustum.intersects(bounds) {
                state.stats.culledInstances += 1
                continue
            }
            if !pipelineBound {
                encoder.setRenderPipelineState(shadow.pipelines.terrain)
                pipelineBound = true
            }
            let uniformOffset = writeShadowDrawUniforms(
                slot: state.slot,
                draw: state.drawCursor,
                lightViewProjection: context.cascade.viewProjection,
                modelMatrix: item.modelMatrix,
                material: item.material
            )
            state.drawCursor += 1
            state.stats.drawCalls += 1
            state.stats.drawnInstances += 1
            argumentTable.setAddress(
                item.mesh.vertexBuffer.gpuAddress,
                index: BufferIndex.vertices.rawValue
            )
            argumentTable.setAddress(
                shadowDrawUniformBuffer.gpuAddress + UInt64(uniformOffset),
                index: BufferIndex.drawUniforms.rawValue
            )
            encoder.setCullMode(.back)
            encoder.drawIndexedPrimitives(
                primitiveType: .triangle,
                indexCount: item.mesh.indexCount,
                indexType: .uint16,
                indexBuffer: item.mesh.indexBuffer.gpuAddress,
                indexBufferLength: item.mesh.indexBuffer.length
            )
        }
    }

    // MARK: - Shared binds

    /// Depth-only render pass targeting one cascade slice of the shadow array.
    private func makeShadowEncoder(cascade: Int) -> MTL4RenderCommandEncoder? {
        let descriptor = MTL4RenderPassDescriptor()
        descriptor.depthAttachment.texture = shadow.map
        descriptor.depthAttachment.slice = cascade
        descriptor.depthAttachment.loadAction = .clear
        descriptor.depthAttachment.storeAction = .store
        descriptor.depthAttachment.clearDepth = 1
        return commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
    }

    private func bindShadowSkinning(for mesh: RenderMesh, slot: Int) {
        guard
            let skinning = mesh.skinningBuffer,
            let matrices = mesh.boneMatrixBuffer
        else { return }
        argumentTable.setAddress(
            skinning.gpuAddress,
            index: BufferIndex.skinningAttributes.rawValue
        )
        argumentTable.setAddress(
            matrices.gpuAddress + UInt64(mesh.boneMatrixOffset(slot: slot)),
            index: BufferIndex.boneMatrices.rawValue
        )
        prepareBoneMatricesOnce(for: mesh, slot: slot)
    }

    /// Skinned casters always use the skinned depth pipeline (skips alpha
    /// discard for skinned cutouts -> conservative solid shadow).
    private func shadowPipeline(
        group: DrawGroup,
        alphaTested: Bool
    ) -> MTLRenderPipelineState {
        if group.faceMorph != nil {
            return shadow.pipelines.morphedSkinned
        }
        if group.mesh.isSkinned {
            return shadow.pipelines.skinned
        }
        return alphaTested ? shadow.pipelines.alphaTest : shadow.pipelines.staticCaster
    }

    /// Writes one ShadowDrawUniforms into the shadow draw ring at
    /// (slot, draw). Ring stride is ShadowConstantCascadeCount * the draw-slot
    /// capacity, so every cascade's draws for the frame fit without collision.
    private func writeShadowDrawUniforms(
        slot: Int,
        draw: Int,
        lightViewProjection: float4x4,
        modelMatrix: float4x4,
        material: RenderMaterial
    ) -> Int {
        let capacity = Self.shadowDrawCapacity(drawUniformSlotCapacity)
        let offset = Self.alignedDrawUniformsSize * (slot * capacity + draw)
        var uniforms = ShadowDrawUniforms(
            lightViewProjection: lightViewProjection,
            modelMatrix: modelMatrix,
            uvOffset: material.uvOffset,
            uvScale: material.uvScale,
            alphaThreshold: material.alphaTestThreshold ?? 0
        )
        shadowDrawUniformBuffer.contents().advanced(by: offset)
            .copyMemory(from: &uniforms, byteCount: MemoryLayout<ShadowDrawUniforms>.size)
        return offset
    }
}
