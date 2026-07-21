// Sun-shadow depth pre-pass (M7.1.1), split from RendererScenePass.swift
// (file-length limits). Runs on the same reused MTL4CommandBuffer BEFORE the
// scene pass: fits ShadowConstantCascadeCount orthographic cascades to the
// camera frustum (ShadowCascadeMath), renders every opaque/alpha/terrain
// caster into one shadow-array slice per cascade, then the scene pass samples
// the array. Water, sky and LOD do not cast. Caster instances + per-draw
// uniforms use dedicated shadow rings so they never collide with the scene
// pass, which resets its own cursors to 0 each frame.

import Metal
import simd

extension Renderer {
    /// One opaque/alpha caster group's shadow-pass residence: all its instances
    /// written once into the shadow instance ring, plus the merged world bounds
    /// used to cull the whole group per cascade. nil bounds -> never culled.
    private struct ShadowCasterGroup {
        let mesh: RenderMesh
        let material: RenderMaterial
        let alphaTested: Bool
        let instanceByteOffset: Int
        let instanceCount: Int
        let bounds: ModelBounds?
    }

    /// Per-cascade encode context: the open depth encoder plus the cascade's
    /// transform, caster-culling frustum, and this frame's ring slot.
    private struct ShadowCascadeContext {
        let cascade: ShadowCascade
        let frustum: Frustum
        let slot: Int
        let encoder: MTL4RenderCommandEncoder
    }

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

    /// Encodes the whole shadow pre-pass onto the open command buffer. Returns
    /// false only when a cascade encoder cannot be created (caller aborts the
    /// frame); an idle pass (shadows off / no casters) returns true having
    /// reset the per-frame shadow state so the scene pass shades unshadowed.
    func encodeShadowPass(slot: Int, projection: float4x4) -> Bool {
        // First encode step of the frame -> owns the shared per-frame reset.
        frameBonePrepared.removeAll(keepingCapacity: true)
        shadowCascades = []
        shadowsActiveThisFrame = false

        guard sunShadowsEnabled else { return true }
        let hasCasters = !scene.opaque.isEmpty || !scene.alphaTested.isEmpty
            || !scene.terrain.isEmpty
        guard hasCasters else { return true }

        let (fovY, aspect) = Self.fovAspect(from: projection)
        let cascades = ShadowCascadeMath.makeCascades(
            cameraToWorld: freeFlyCamera.viewMatrix().inverse,
            fovYRadians: fovY,
            aspectRatio: aspect,
            nearPlane: Self.nearPlane,
            shadowDistance: Self.shadowDistance,
            sunDirection: sunTravelDirection,
            cascadeCount: ShadowConstant.cascadeCount.rawValue,
            lambda: Self.shadowSplitLambda,
            shadowMapResolution: ShadowConstant.mapResolution.rawValue,
            casterBackup: Self.shadowCasterBackup
        )

        let casters = writeShadowCasters(slot: slot)
        var drawCursor = 0
        for (index, cascade) in cascades.enumerated() {
            guard let encoder = makeShadowEncoder(cascade: index) else { return false }
            encoder.label = "Shadow Cascade \(index)"
            encoder.setArgumentTable(argumentTable, stages: [.vertex, .fragment])
            encoder.setDepthStencilState(depthState)
            encoder.setFrontFacing(.counterClockwise)
            encoder.setDepthBias(
                Self.shadowDepthBias,
                slopeScale: Self.shadowSlopeScale,
                clamp: 0
            )
            argumentTable.setSamplerState(
                sampler.gpuResourceID,
                index: SamplerIndex.trilinear.rawValue
            )
            let context = ShadowCascadeContext(
                cascade: cascade,
                frustum: Frustum(viewProjection: cascade.viewProjection),
                slot: slot,
                encoder: encoder
            )
            encodeShadowCasters(casters, in: context, drawCursor: &drawCursor)
            encoder.endEncoding()
        }
        shadowCascades = cascades
        shadowsActiveThisFrame = true
        return true
    }

    /// Writes every opaque + alpha caster's instance transforms once into this
    /// frame's shadow instance ring (no per-instance culling in 7.1.1) and
    /// returns per-group offsets/counts/bounds for the per-cascade draws.
    private func writeShadowCasters(slot: Int) -> [ShadowCasterGroup] {
        let stride = MemoryLayout<InstanceTransform>.stride
        let base = slot * instanceSlotCapacity
        var cursor = 0
        var result: [ShadowCasterGroup] = []
        func append(_ groups: [DrawGroup], alphaTested: Bool) {
            for group in groups where !group.instances.isEmpty {
                let byteOffset = (base + cursor) * stride
                for instance in group.instances {
                    var transform = InstanceTransform(
                        modelMatrix: instance.modelMatrix,
                        normalMatrix: instance.normalMatrix
                    )
                    shadowInstanceBuffer.contents()
                        .advanced(by: (base + cursor) * stride)
                        .copyMemory(
                            from: &transform,
                            byteCount: MemoryLayout<InstanceTransform>.size
                        )
                    cursor += 1
                }
                result.append(ShadowCasterGroup(
                    mesh: group.mesh,
                    material: group.material,
                    alphaTested: alphaTested,
                    instanceByteOffset: byteOffset,
                    instanceCount: group.instances.count,
                    bounds: Self.mergedBounds(group)
                ))
            }
        }
        append(scene.opaque, alphaTested: false)
        append(scene.alphaTested, alphaTested: true)
        return result
    }

    /// Union of the group's per-instance world AABBs. Any unbounded instance
    /// forces nil (never cull the group) — matches the scene pass's rule.
    private static func mergedBounds(_ group: DrawGroup) -> ModelBounds? {
        var result: ModelBounds?
        for instance in group.instances {
            guard let bounds = instance.bounds else { return nil }
            result = result.map { $0.union(bounds) } ?? bounds
        }
        return result
    }

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

    /// Draws every caster whose bounds intersect this cascade. Static/skinned
    /// share the instance ring written once; terrain writes its model matrix
    /// into the shadow draw ring. Pipeline switches lazily on caster kind.
    private func encodeShadowCasters(
        _ casters: [ShadowCasterGroup],
        in context: ShadowCascadeContext,
        drawCursor: inout Int
    ) {
        let encoder = context.encoder
        var boundPipeline: ObjectIdentifier?
        for group in casters {
            if let bounds = group.bounds, !context.frustum.intersects(bounds) {
                continue
            }
            let skinned = group.mesh.isSkinned
            let pipeline = shadowPipeline(skinned: skinned, alphaTested: group.alphaTested)
            if boundPipeline != ObjectIdentifier(pipeline) {
                encoder.setRenderPipelineState(pipeline)
                boundPipeline = ObjectIdentifier(pipeline)
            }
            let uniformOffset = writeShadowDrawUniforms(
                slot: context.slot,
                draw: drawCursor,
                lightViewProjection: context.cascade.viewProjection,
                modelMatrix: matrix_identity_float4x4,
                material: group.material
            )
            drawCursor += 1
            argumentTable.setAddress(
                group.mesh.vertexBuffer.gpuAddress,
                index: BufferIndex.vertices.rawValue
            )
            argumentTable.setAddress(
                shadowDrawUniformBuffer.gpuAddress + UInt64(uniformOffset),
                index: BufferIndex.drawUniforms.rawValue
            )
            argumentTable.setAddress(
                shadowInstanceBuffer.gpuAddress + UInt64(group.instanceByteOffset),
                index: BufferIndex.instanceTransforms.rawValue
            )
            if skinned {
                bindShadowSkinning(for: group.mesh, slot: context.slot)
            }
            if group.alphaTested {
                argumentTable.setTexture(
                    group.material.diffuse.gpuResourceID,
                    index: TextureIndex.diffuse.rawValue
                )
            }
            encoder.setCullMode(group.material.doubleSided ? .none : .back)
            encoder.drawIndexedPrimitives(
                primitiveType: .triangle,
                indexCount: group.mesh.indexCount,
                indexType: .uint16,
                indexBuffer: group.mesh.indexBuffer.gpuAddress,
                indexBufferLength: group.mesh.indexBuffer.length,
                instanceCount: group.instanceCount
            )
        }
        encodeShadowTerrain(in: context, drawCursor: &drawCursor)
    }

    private func encodeShadowTerrain(
        in context: ShadowCascadeContext,
        drawCursor: inout Int
    ) {
        let encoder = context.encoder
        var pipelineBound = false
        for item in scene.terrain {
            if let bounds = item.bounds, !context.frustum.intersects(bounds) {
                continue
            }
            if !pipelineBound {
                encoder.setRenderPipelineState(shadow.pipelines.terrain)
                pipelineBound = true
            }
            let uniformOffset = writeShadowDrawUniforms(
                slot: context.slot,
                draw: drawCursor,
                lightViewProjection: context.cascade.viewProjection,
                modelMatrix: item.modelMatrix,
                material: item.material
            )
            drawCursor += 1
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

    /// Skinned casters always use the skinned depth pipeline (7.1.1 skips alpha
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
