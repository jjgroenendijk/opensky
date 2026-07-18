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
    /// encoder + frame slot + frustum, the running visible-draw cursor into
    /// the per-draw uniform ring, and the accumulating draw stats.
    struct ScenePassState {
        let encoder: MTL4RenderCommandEncoder
        let slot: Int
        let frustum: Frustum
        var drawCursor = 0
        var stats = SceneDrawStats()
    }

    // MARK: - Uniform writes

    /// Writes this frame's uniforms into its 256-byte-aligned slot and
    /// returns the byte offset of that slot. `viewProjection` is computed by
    /// the caller (encodeScenePass shares it with the frustum). Sun/ambient
    /// come from the injected SceneCamera.
    private func updateFrameUniforms(slot: Int, viewProjection: float4x4) -> Int {
        let offset = Self.alignedFrameUniformsSize * slot
        var uniforms = FrameUniforms(
            viewProjectionMatrix: viewProjection,
            cameraPosition: freeFlyCamera.position,
            sunDirection: camera.sunDirection,
            sunColor: camera.sunColor,
            ambientColor: camera.ambientColor
        )
        frameUniformBuffer.contents().advanced(by: offset)
            .copyMemory(from: &uniforms, byteCount: MemoryLayout<FrameUniforms>.size)
        return offset
    }

    /// Writes one draw's uniforms into the ring and returns its byte offset.
    private func updateDrawUniforms(slot: Int, draw: Int, item: DrawItem) -> Int {
        let offset = Self.alignedDrawUniformsSize * (slot * scene.drawCount + draw)
        var uniforms = DrawUniforms(
            modelMatrix: item.modelMatrix,
            normalMatrix: item.normalMatrix,
            uvOffset: item.material.uvOffset,
            uvScale: item.material.uvScale,
            materialAlpha: item.material.alpha,
            alphaThreshold: item.material.alphaTestThreshold ?? 0
        )
        drawUniformBuffer.contents().advanced(by: offset)
            .copyMemory(from: &uniforms, byteCount: MemoryLayout<DrawUniforms>.size)
        return offset
    }

    /// Terrain variant of updateDrawUniforms: same ring, same aligned slots
    /// (slot size covers both structs), TerrainDrawUniforms layout.
    private func updateTerrainDrawUniforms(
        slot: Int,
        draw: Int,
        item: TerrainDrawItem
    ) -> Int {
        let offset = Self.alignedDrawUniformsSize * (slot * scene.drawCount + draw)
        var uniforms = TerrainDrawUniforms(
            modelMatrix: item.modelMatrix,
            normalMatrix: item.normalMatrix,
            uvOffset: item.material.uvOffset,
            uvScale: item.material.uvScale,
            layerCount: UInt32(min(item.layerTextures.count, TerrainConstant.maxLayers.rawValue))
        )
        drawUniformBuffer.contents().advanced(by: offset)
            .copyMemory(from: &uniforms, byteCount: MemoryLayout<TerrainDrawUniforms>.size)
        return offset
    }

    // MARK: - Draw encode

    private func encode(
        items: [DrawItem],
        pipeline: MTLRenderPipelineState,
        state: inout ScenePassState
    ) {
        guard !items.isEmpty else { return }
        // Pipeline bound lazily: an all-culled list encodes nothing.
        var pipelineBound = false
        for item in items {
            if let bounds = item.bounds, !state.frustum.intersects(bounds) {
                state.stats.culledInstances += 1
                continue
            }
            if !pipelineBound {
                state.encoder.setRenderPipelineState(pipeline)
                pipelineBound = true
            }
            // Running visible-draw cursor indexes the uniform ring: visible
            // count <= scene.drawCount = ring capacity, so always in range.
            let uniformOffset = updateDrawUniforms(
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
            argumentTable.setTexture(
                item.material.diffuse.gpuResourceID,
                index: TextureIndex.diffuse.rawValue
            )
            state.encoder.setCullMode(item.material.doubleSided ? .none : .back)
            state.encoder.drawIndexedPrimitives(
                primitiveType: .triangle,
                indexCount: item.mesh.indexCount,
                indexType: .uint16,
                indexBuffer: item.mesh.indexBuffer.gpuAddress,
                indexBufferLength: item.mesh.indexBuffer.length
            )
        }
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
            let uniformOffset = updateTerrainDrawUniforms(
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
                item.weightsBuffer.gpuAddress,
                index: BufferIndex.terrainWeights.rawValue
            )
            argumentTable.setAddress(
                drawUniformBuffer.gpuAddress + UInt64(uniformOffset),
                index: BufferIndex.drawUniforms.rawValue
            )
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
        encoder.setDepthStencilState(depthState)
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
        var state = ScenePassState(encoder: encoder, slot: slot, frustum: frustum)
        encode(items: scene.opaque, pipeline: opaquePipeline, state: &state)
        encodeTerrain(items: scene.terrain, state: &state)
        encode(items: scene.alphaTested, pipeline: alphaTestPipeline, state: &state)
        lastDrawStats = state.stats
        encoder.endEncoding()
        return true
    }
}
