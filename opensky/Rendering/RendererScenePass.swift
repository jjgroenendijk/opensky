// Scene-pass encode path, split from Renderer.swift (file-length limits,
// RendererSetup.swift precedent): per-frame + per-draw uniform writes, the
// frustum-culled static/terrain encoders, and the single-pass scene encode.
// Members it touches stay internal on Renderer (cross-file extension); the
// module boundary still hides them from callers.

import Metal
import MetalKit
import simd

extension Renderer {
    /// Mutable state threaded through one scene pass's encoders: the open
    /// encoder + frame slot + frustum, the running cursors into the
    /// per-draw uniform ring (visible groups) and the per-instance
    /// transform ring (visible instances), and the accumulating draw stats.
    struct ScenePassState {
        let encoder: MTL4RenderCommandEncoder
        let slot: Int
        let frustum: Frustum
        var drawCursor = 0
        var instanceCursor = 0
        var stats = SceneDrawStats()
    }

    // MARK: - Uniform writes

    /// Writes this frame's uniforms into its 256-byte-aligned slot and
    /// returns the byte offset of that slot. `viewProjection` is computed by
    /// the caller (encodeScenePass shares it with the frustum). Sun/ambient
    /// come from the injected SceneCamera.
    private func updateFrameUniforms(slot: Int, viewProjection: float4x4) -> Int {
        let offset = Self.alignedFrameUniformsSize * slot
        let lighting = scene.lighting
        let ambient = lighting?.directionalAmbient ?? .black
        let fog = lighting?.fog
        var uniforms = FrameUniforms(
            viewProjectionMatrix: viewProjection,
            cameraPosition: freeFlyCamera.position,
            sunDirection: lighting?.directionalDirection ?? camera.sunDirection,
            sunColor: lighting?.directionalColor ?? camera.sunColor,
            ambientColor: lighting?.ambientColor ?? camera.ambientColor,
            directionalAmbientPositiveX: ambient.positiveX,
            directionalAmbientNegativeX: ambient.negativeX,
            directionalAmbientPositiveY: ambient.positiveY,
            directionalAmbientNegativeY: ambient.negativeY,
            directionalAmbientPositiveZ: ambient.positiveZ,
            directionalAmbientNegativeZ: ambient.negativeZ,
            fogNearColor: fog?.nearColor ?? .zero,
            fogFarColor: fog?.farColor ?? .zero,
            fogDistances: SIMD4(
                fog?.nearDistance ?? 0,
                fog?.farDistance ?? 1,
                fog?.power ?? 1,
                fog?.maximum ?? 0
            ),
            fogEnabled: fog == nil ? 0 : 1,
            timeOfDayHours: timeOfDay,
            animationTime: Float(frameIndex) / 60
        )
        frameUniformBuffer.contents().advanced(by: offset)
            .copyMemory(from: &uniforms, byteCount: MemoryLayout<FrameUniforms>.size)
        return offset
    }

    /// Writes one group's material scalars into the ring and returns the
    /// byte offset. Ring stride is the (possibly regrown) slot capacity,
    /// not drawCount. Matrices live per instance (writeVisibleInstances).
    private func updateDrawUniforms(
        slot: Int,
        draw: Int,
        material: RenderMaterial,
        pointLightCount: Int
    ) -> Int {
        let offset = Self.alignedDrawUniformsSize * (slot * drawUniformSlotCapacity + draw)
        var uniforms = DrawUniforms(
            uvOffset: material.uvOffset,
            uvScale: material.uvScale,
            materialAlpha: material.alpha,
            alphaThreshold: material.alphaTestThreshold ?? 0,
            pointLightCount: UInt32(pointLightCount)
        )
        drawUniformBuffer.contents().advanced(by: offset)
            .copyMemory(from: &uniforms, byteCount: MemoryLayout<DrawUniforms>.size)
        return offset
    }

    /// Selects + writes nearest supported point lights for one draw. Returns
    /// count plus byte offset bound at BufferIndexPointLights.
    private func writePointLights(
        near position: SIMD3<Float>,
        slot: Int,
        draw: Int
    ) -> (count: Int, byteOffset: Int) {
        let limit = LightingConstant.maxPointLights.rawValue
        let lights = scene.nearestPointLights(to: position, limit: limit)
        let stride = MemoryLayout<PointLightUniform>.stride
        let first = (slot * drawUniformSlotCapacity + draw) * limit
        for (index, light) in lights.enumerated() {
            var uniform = PointLightUniform(
                positionRadius: SIMD4(light.position, light.radius),
                colorFalloff: SIMD4(light.color, light.falloffExponent)
            )
            pointLightBuffer.contents().advanced(by: (first + index) * stride)
                .copyMemory(from: &uniform, byteCount: MemoryLayout<PointLightUniform>.size)
        }
        return (lights.count, first * stride)
    }

    private func lightingCenter(of group: DrawGroup) -> SIMD3<Float> {
        let sum = group.instances.reduce(SIMD3<Float>.zero) { partial, instance in
            partial + SIMD3(
                instance.modelMatrix.columns.3.x,
                instance.modelMatrix.columns.3.y,
                instance.modelMatrix.columns.3.z
            )
        }
        return sum / Float(max(1, group.instances.count))
    }

    /// Writes the group's frustum-surviving instance transforms tightly
    /// packed from the current instance cursor; returns the visible count
    /// and the byte offset the group's draw binds the transform ring at.
    /// Total written per frame <= scene.instanceCount <= ring capacity.
    private func writeVisibleInstances(
        of group: DrawGroup,
        state: inout ScenePassState
    ) -> (written: Int, byteOffset: Int) {
        let stride = MemoryLayout<InstanceTransform>.stride
        let base = state.slot * instanceSlotCapacity + state.instanceCursor
        var written = 0
        for instance in group.instances {
            if let bounds = instance.bounds, !state.frustum.intersects(bounds) {
                state.stats.culledInstances += 1
                continue
            }
            var transforms = InstanceTransform(
                modelMatrix: instance.modelMatrix,
                normalMatrix: instance.normalMatrix
            )
            instanceTransformBuffer.contents()
                .advanced(by: (base + written) * stride)
                .copyMemory(from: &transforms, byteCount: MemoryLayout<InstanceTransform>.size)
            written += 1
        }
        state.instanceCursor += written
        state.stats.drawnInstances += written
        return (written, base * stride)
    }

    /// Terrain variant of updateDrawUniforms: same ring, same aligned slots
    /// (slot size covers both structs), TerrainDrawUniforms layout.
    private func updateTerrainDrawUniforms(
        slot: Int,
        draw: Int,
        item: TerrainDrawItem,
        pointLightCount: Int
    ) -> Int {
        let offset = Self.alignedDrawUniformsSize * (slot * drawUniformSlotCapacity + draw)
        var uniforms = TerrainDrawUniforms(
            modelMatrix: item.modelMatrix,
            normalMatrix: item.normalMatrix,
            uvOffset: item.material.uvOffset,
            uvScale: item.material.uvScale,
            layerCount: UInt32(min(item.layerTextures.count, TerrainConstant.maxLayers.rawValue)),
            pointLightCount: UInt32(pointLightCount)
        )
        drawUniformBuffer.contents().advanced(by: offset)
            .copyMemory(from: &uniforms, byteCount: MemoryLayout<TerrainDrawUniforms>.size)
        return offset
    }

    private func updateWaterDrawUniforms(
        slot: Int,
        draw: Int,
        item: WaterDrawItem
    ) -> Int {
        let offset = Self.alignedDrawUniformsSize * (slot * drawUniformSlotCapacity + draw)
        var uniforms = WaterDrawUniforms(
            modelMatrix: item.modelMatrix,
            shallowColor: item.shallowColor,
            deepColor: item.deepColor,
            reflectionColor: item.reflectionColor
        )
        drawUniformBuffer.contents().advanced(by: offset)
            .copyMemory(from: &uniforms, byteCount: MemoryLayout<WaterDrawUniforms>.size)
        return offset
    }

    // MARK: - Draw encode

    /// Encodes instanced draw groups: per group, cull per instance, write
    /// only the visible instances' transforms, bind the transform ring at
    /// the group's base offset ([[instance_id]] starts at 0 per draw), and
    /// draw once with the visible instanceCount. All-culled groups encode
    /// nothing and consume no uniform slot.
    private func encode(
        groups: [DrawGroup],
        staticPipeline: MTLRenderPipelineState,
        skinnedPipeline: MTLRenderPipelineState,
        state: inout ScenePassState
    ) {
        guard !groups.isEmpty else { return }
        // Pipeline bound lazily: an all-culled list encodes nothing. Model
        // ordering is retained, so switch only when rigid/skinned kind does.
        var boundSkinned: Bool?
        for group in groups {
            let visible = writeVisibleInstances(of: group, state: &state)
            guard visible.written > 0 else { continue }
            if boundSkinned != group.mesh.isSkinned {
                state.encoder.setRenderPipelineState(
                    group.mesh.isSkinned ? skinnedPipeline : staticPipeline
                )
                boundSkinned = group.mesh.isSkinned
            }
            // Running visible-group cursor indexes the uniform ring:
            // visible groups <= scene.drawCount <= ring capacity.
            let lightOffset = writePointLights(
                near: lightingCenter(of: group),
                slot: state.slot,
                draw: state.drawCursor
            )
            let uniformOffset = updateDrawUniforms(
                slot: state.slot,
                draw: state.drawCursor,
                material: group.material,
                pointLightCount: lightOffset.count
            )
            state.drawCursor += 1
            state.stats.drawCalls += 1
            argumentTable.setAddress(
                group.mesh.vertexBuffer.gpuAddress,
                index: BufferIndex.vertices.rawValue
            )
            bindSkinningBuffers(for: group.mesh)
            argumentTable.setAddress(
                drawUniformBuffer.gpuAddress + UInt64(uniformOffset),
                index: BufferIndex.drawUniforms.rawValue
            )
            argumentTable.setAddress(
                instanceTransformBuffer.gpuAddress + UInt64(visible.byteOffset),
                index: BufferIndex.instanceTransforms.rawValue
            )
            argumentTable.setAddress(
                pointLightBuffer.gpuAddress + UInt64(lightOffset.byteOffset),
                index: BufferIndex.pointLights.rawValue
            )
            argumentTable.setTexture(
                group.material.diffuse.gpuResourceID,
                index: TextureIndex.diffuse.rawValue
            )
            state.encoder.setCullMode(group.material.doubleSided ? .none : .back)
            state.encoder.drawIndexedPrimitives(
                primitiveType: .triangle,
                indexCount: group.mesh.indexCount,
                indexType: .uint16,
                indexBuffer: group.mesh.indexBuffer.gpuAddress,
                indexBufferLength: group.mesh.indexBuffer.length,
                instanceCount: visible.written
            )
        }
    }

    private func bindSkinningBuffers(for mesh: RenderMesh) {
        guard
            let skinning = mesh.skinningBuffer,
            let matrices = mesh.boneMatrixBuffer
        else { return }
        argumentTable.setAddress(
            skinning.gpuAddress,
            index: BufferIndex.skinningAttributes.rawValue
        )
        argumentTable.setAddress(
            matrices.gpuAddress,
            index: BufferIndex.boneMatrices.rawValue
        )
    }

    /// Encodes the terrain splat draws: per-quadrant pipeline with the base
    /// diffuse at TextureIndexDiffuse and the ATXT layer array at
    /// TextureIndexTerrainLayer0+. Unused layer slots rebind the base diffuse
    /// so every declared texture argument is valid; the shader never samples
    /// past TerrainDrawUniforms.layerCount.
    private func encodeTerrain(
        items: [TerrainDrawItem],
        state: inout ScenePassState
    ) {
        guard !items.isEmpty else { return }
        var pipelineBound = false
        for item in items {
            if let bounds = item.bounds, !state.frustum.intersects(bounds) {
                state.stats.culledInstances += 1
                continue
            }
            if !pipelineBound {
                state.encoder.setRenderPipelineState(terrainPipeline)
                pipelineBound = true
            }
            let center = item.bounds.map { ($0.min + $0.max) * 0.5 }
                ?? SIMD3(item.modelMatrix.columns.3.x, item.modelMatrix.columns.3.y, 0)
            let lightOffset = writePointLights(
                near: center,
                slot: state.slot,
                draw: state.drawCursor
            )
            let uniformOffset = updateTerrainDrawUniforms(
                slot: state.slot,
                draw: state.drawCursor,
                item: item,
                pointLightCount: lightOffset.count
            )
            state.drawCursor += 1
            state.stats.drawCalls += 1
            state.stats.drawnInstances += 1
            argumentTable.setAddress(
                item.mesh.vertexBuffer.gpuAddress,
                index: BufferIndex.vertices.rawValue
            )
            argumentTable.setAddress(
                item.weightsBuffer.gpuAddress,
                index: BufferIndex.terrainWeights.rawValue
            )
            argumentTable.setAddress(
                drawUniformBuffer.gpuAddress + UInt64(uniformOffset),
                index: BufferIndex.drawUniforms.rawValue
            )
            argumentTable.setAddress(
                pointLightBuffer.gpuAddress + UInt64(lightOffset.byteOffset),
                index: BufferIndex.pointLights.rawValue
            )
            bindTerrainTextures(for: item)
            state.encoder.setCullMode(.back)
            state.encoder.drawIndexedPrimitives(
                primitiveType: .triangle,
                indexCount: item.mesh.indexCount,
                indexType: .uint16,
                indexBuffer: item.mesh.indexBuffer.gpuAddress,
                indexBufferLength: item.mesh.indexBuffer.length
            )
        }
    }

    private func bindTerrainTextures(for item: TerrainDrawItem) {
        argumentTable.setTexture(
            item.material.diffuse.gpuResourceID,
            index: TextureIndex.diffuse.rawValue
        )
        for layerSlot in 0 ..< TerrainConstant.maxLayers.rawValue {
            let texture = layerSlot < item.layerTextures.count
                ? item.layerTextures[layerSlot]
                : item.material.diffuse
            argumentTable.setTexture(
                texture.gpuResourceID,
                index: TextureIndex.terrainLayer0.rawValue + layerSlot
            )
        }
    }

    /// Water renders after opaque + cutout geometry. Depth is read-only;
    /// straight-alpha blend exposes terrain/objects beneath the surface.
    private func encodeWater(
        items: [WaterDrawItem],
        state: inout ScenePassState
    ) {
        guard !items.isEmpty else { return }
        var pipelineBound = false
        for item in items {
            if let bounds = item.bounds, !state.frustum.intersects(bounds) {
                state.stats.culledInstances += 1
                continue
            }
            if !pipelineBound {
                state.encoder.setRenderPipelineState(waterPipeline)
                state.encoder.setDepthStencilState(waterDepthState)
                pipelineBound = true
            }
            let uniformOffset = updateWaterDrawUniforms(
                slot: state.slot,
                draw: state.drawCursor,
                item: item
            )
            state.drawCursor += 1
            state.stats.drawCalls += 1
            state.stats.drawnInstances += 1
            argumentTable.setAddress(
                item.mesh.vertexBuffer.gpuAddress,
                index: BufferIndex.vertices.rawValue
            )
            argumentTable.setAddress(
                drawUniformBuffer.gpuAddress + UInt64(uniformOffset),
                index: BufferIndex.drawUniforms.rawValue
            )
            state.encoder.setCullMode(.none)
            state.encoder.drawIndexedPrimitives(
                primitiveType: .triangle,
                indexCount: item.mesh.indexCount,
                indexType: .uint16,
                indexBuffer: item.mesh.indexBuffer.gpuAddress,
                indexBufferLength: item.mesh.indexBuffer.length
            )
        }
    }

    /// Encodes the whole scene as one render pass into the open command
    /// buffer. Returns false when the encoder cannot be created.
    func encodeScenePass(
        descriptor: MTL4RenderPassDescriptor,
        slot: Int,
        projection: float4x4
    ) -> Bool {
        // One frustum per frame from the same view-projection the shaders
        // get — culling can never disagree with what the GPU would clip.
        let viewProjection = projection * freeFlyCamera.viewMatrix()
        let frustum = Frustum(viewProjection: viewProjection)
        let frameOffset = updateFrameUniforms(slot: slot, viewProjection: viewProjection)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return false }
        encoder.label = "Static Mesh Encoder"
        // Winding per docs/decisions/coordinates.md (verified on the demo
        // scene ground plane): faces authored counter-clockwise seen from
        // outside are front under our view/projection.
        encoder.setFrontFacing(.counterClockwise)
        encoder.setArgumentTable(argumentTable, stages: [.vertex, .fragment])
        argumentTable.setAddress(
            frameUniformBuffer.gpuAddress + UInt64(frameOffset),
            index: BufferIndex.frameUniforms.rawValue
        )
        argumentTable.setSamplerState(
            sampler.gpuResourceID,
            index: SamplerIndex.trilinear.rawValue
        )
        if scene.sky != nil {
            encoder.setRenderPipelineState(skyPipeline)
            encoder.setCullMode(.none)
            encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.setDepthStencilState(depthState)
        var state = ScenePassState(encoder: encoder, slot: slot, frustum: frustum)
        encode(
            groups: scene.opaque,
            staticPipeline: opaquePipeline,
            skinnedPipeline: skinnedOpaquePipeline,
            state: &state
        )
        encodeTerrain(items: scene.terrain, state: &state)
        encode(
            groups: scene.alphaTested,
            staticPipeline: alphaTestPipeline,
            skinnedPipeline: skinnedAlphaTestPipeline,
            state: &state
        )
        encodeWater(items: scene.water, state: &state)
        lastDrawStats = state.stats
        encoder.endEncoding()
        return true
    }
}
