// Sun-shadow depth pre-pass (M7.1.1, per-cascade caster culling in M7.1.2),
// split from RendererScenePass.swift (file-length limits). Runs on the same
// reused MTL4CommandBuffer BEFORE the scene pass: fits orthographic cascades
// to the camera frustum (ShadowCascadeMath), renders the casters whose bounds
// intersect each cascade into one shadow-array slice per cascade, then the
// scene pass samples the array. Water, sky and LOD do not cast. Caster
// instances + per-draw uniforms use dedicated shadow rings so they never
// collide with the scene pass, which resets its own cursors to 0 each frame.

import Foundation
import Metal
import simd

/// Sun-shadow quality tier (M7.1.2). Drives cascade count, shadow range, and
/// PCF tap count; the app sidebar selects it. `.off` renders no shadow pass
/// (equivalent to `sunShadowsEnabled = false`, but a persisted user choice).
nonisolated enum ShadowQuality: String, CaseIterable {
    case off
    case low
    case high
}

/// Per-frame shadow-pass culling + draw accounting, mirror of SceneDrawStats:
/// deterministic evidence for the per-cascade caster-culling tests and budget
/// triage. Counts are summed across every rendered cascade.
nonisolated struct ShadowDrawStats: Equatable {
    /// drawIndexedPrimitives calls encoded (all cascades).
    var drawCalls = 0
    /// Caster instances drawn after per-cascade frustum culling (static +
    /// terrain), summed across cascades.
    var drawnInstances = 0
    /// (instance, cascade) pairs the frustum test skipped this frame.
    var culledInstances = 0
    /// Cascade slices actually rendered (2 low, 3 high).
    var cascadesRendered = 0
}

extension Renderer {
    /// Per-cascade encode context: the open depth encoder plus the cascade's
    /// transform, caster-culling frustum, and this frame's ring slot.
    private struct ShadowCascadeContext {
        let cascade: ShadowCascade
        let frustum: Frustum
        let slot: Int
        let encoder: MTL4RenderCommandEncoder
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
    var shadowRenders: Bool {
        sunShadowsEnabled && shadowQuality != .off
    }

    /// Cascades to render: 2 for low (cheaper), 3 for high. The shadow map
    /// keeps all ShadowConstantCascadeCount slices allocated either way; low
    /// simply renders fewer and the shader pads the unused splits.
    var shadowCascadeCount: Int {
        shadowQuality == .low ? 2 : ShadowConstant.cascadeCount.rawValue
    }

    /// Sun-shadow far bound for the active quality.
    var activeShadowDistance: Float {
        shadowQuality == .low ? Self.shadowDistanceLow : Self.shadowDistance
    }

    /// PCF kernel radius bound into FrameUniforms: 0 -> single compare tap
    /// (low), 1 -> the 3x3 kernel (high). Read by sunShadowFactor.
    var shadowSampleRadius: UInt32 {
        shadowQuality == .low ? 0 : 1
    }

    /// Shadow instance-ring slots one frame slot can need: every scene
    /// instance drawn in every cascade (per-cascade contiguous runs).
    var shadowInstanceSlotCapacity: Int {
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
    func shadowCascadeMatrix(_ index: Int) -> float4x4 {
        index < shadowCascades.count ? shadowCascades[index].viewProjection
            : matrix_identity_float4x4
    }

    /// Per-cascade far bounds packed for the shader, padded with the last real
    /// bound (mirrors ShadowCascadeMath.cascadeIndex padding).
    func shadowCascadeSplitBounds() -> SIMD4<Float> {
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
    func encodeShadowPass(slot: Int, projection: float4x4) -> Bool {
        let started = DispatchTime.now().uptimeNanoseconds
        defer {
            lastShadowUpdateMS =
                Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        }
        // First encode step of the frame -> owns the shared per-frame reset.
        frameBonePrepared.removeAll(keepingCapacity: true)
        shadowCascades = []
        shadowsActiveThisFrame = false
        lastShadowDrawStats = ShadowDrawStats()

        guard shadowRenders else { return true }
        let hasCasters = scene.opaque.contains(where: \.castsShadows)
            || scene.alphaTested.contains(where: \.castsShadows)
            || !scene.terrain.isEmpty
        guard hasCasters else { return true }

        let (fovY, aspect) = Self.fovAspect(from: projection)
        let cascades = ShadowCascadeMath.makeCascades(
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
        )

        var state = ShadowPassState(slot: slot, base: slot * shadowInstanceSlotCapacity)
        guard encodeCascades(cascades, state: &state) else { return false }
        lastShadowDrawStats = state.stats
        shadowCascades = cascades
        shadowsActiveThisFrame = true
        return true
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
                slot: state.slot,
                encoder: encoder
            )
            encodeCasterGroups(scene.opaque, alphaTested: false, in: context, state: &state)
            encodeCasterGroups(scene.alphaTested, alphaTested: true, in: context, state: &state)
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
    /// terrain). The scene IS the resident cell set, so this bounds the
    /// geometry the sun can actually shadow — used to clamp each cascade's
    /// caster backup. nil when any caster is unbounded (conservative: no clamp).
    private func residentCasterBounds() -> ModelBounds? {
        var result: ModelBounds?
        func merge(_ bounds: ModelBounds?) -> Bool {
            guard let bounds else { return false }
            result = result.map { $0.union(bounds) } ?? bounds
            return true
        }
        for group in scene.opaque {
            guard group.castsShadows else { continue }
            for instance in group.instances where !merge(instance.bounds) {
                return nil
            }
        }
        for group in scene.alphaTested {
            guard group.castsShadows else { continue }
            for instance in group.instances where !merge(instance.bounds) {
                return nil
            }
        }
        for item in scene.terrain where !merge(item.bounds) {
            return nil
        }
        return result
    }

    // MARK: - Caster culling + draw

    /// Per group: cull per instance against this cascade's frustum, append the
    /// survivors' transforms into the shadow instance ring, draw once with the
    /// surviving instanceCount. Pipeline switches lazily on caster kind.
    private func encodeCasterGroups(
        _ groups: [DrawGroup],
        alphaTested: Bool,
        in context: ShadowCascadeContext,
        state: inout ShadowPassState
    ) {
        var boundPipeline: ObjectIdentifier?
        for group in groups where group.castsShadows {
            let visible = writeVisibleShadowInstances(of: group, in: context, state: &state)
            guard visible.written > 0 else { continue }
            let pipeline = shadowPipeline(skinned: group.mesh.isSkinned, alphaTested: alphaTested)
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
        for instance in group.instances {
            if let bounds = instance.bounds, !context.frustum.intersects(bounds) {
                state.stats.culledInstances += 1
                continue
            }
            var transform = InstanceTransform(
                modelMatrix: instance.modelMatrix,
                normalMatrix: instance.normalMatrix
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
        visible: (written: Int, byteOffset: Int),
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
            shadowInstanceBuffer.gpuAddress + UInt64(visible.byteOffset),
            index: BufferIndex.instanceTransforms.rawValue
        )
        if group.mesh.isSkinned {
            bindShadowSkinning(for: group.mesh, slot: state.slot)
        }
        if alphaTested {
            argumentTable.setTexture(
                group.material.diffuse.gpuResourceID,
                index: TextureIndex.diffuse.rawValue
            )
        }
        context.encoder.setCullMode(group.material.doubleSided ? .none : .back)
        context.encoder.drawIndexedPrimitives(
            primitiveType: .triangle,
            indexCount: group.mesh.indexCount,
            indexType: .uint16,
            indexBuffer: group.mesh.indexBuffer.gpuAddress,
            indexBufferLength: group.mesh.indexBuffer.length,
            instanceCount: visible.written
        )
    }

    private func encodeShadowTerrain(
        in context: ShadowCascadeContext,
        state: inout ShadowPassState
    ) {
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
    private func shadowPipeline(skinned: Bool, alphaTested: Bool) -> MTLRenderPipelineState {
        if skinned {
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
