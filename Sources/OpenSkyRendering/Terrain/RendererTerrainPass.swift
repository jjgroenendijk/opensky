import Metal
import OpenSkyFormatsCore
import OpenSkyRenderCore
import OpenSkyRenderResources
import OpenSkyShaderTypes
import simd

/// The terrain splat draws of the scene pass.
extension Renderer {
    /// Encodes the terrain splat draws: per-quadrant pipeline with the base
    /// diffuse at TextureIndexDiffuse and the ATXT layer array at
    /// TextureIndexTerrainLayer0+, and their normal maps after them. Unused layer
    /// slots rebind the base textures so every declared texture argument is valid; the shader never
    /// samples
    /// past TerrainDrawUniforms.layerCount.
    func encodeTerrain(
        items: [TerrainDrawItem],
        state: inout ScenePassState
    ) {
        guard !items.isEmpty, effectiveRenderLayers.contains(.terrain) else { return }
        var pipelineBound = false
        for item in items {
            if let bounds = item.bounds, !state.frustum.intersects(bounds) {
                state.stats.culledInstances += 1
                continue
            }
            if !pipelineBound {
                state.encoder.setRenderPipelineState(
                    isRenderDebugActive
                        ? debugPipelines.terrain : (rayTracedPipelines?.terrain ?? terrainPipeline)
                )
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
            streamedBinding(item.material.diffuse),
            index: TextureIndex.diffuse.rawValue
        )
        for layerSlot in 0 ..< TerrainConstant.maxLayers.rawValue {
            let texture = layerSlot < item.layerTextures.count
                ? item.layerTextures[layerSlot]
                : item.material.diffuse
            argumentTable.setTexture(
                streamedBinding(texture),
                index: TextureIndex.terrainLayer0.rawValue + layerSlot
            )
            let normal = layerSlot < item.normals.layers.count
                ? item.normals.layers[layerSlot]
                : item.normals.base
            argumentTable.setTexture(
                streamedBinding(normal),
                index: TextureIndex.terrainLayerNormal0.rawValue + layerSlot
            )
        }
        argumentTable.setTexture(
            streamedBinding(item.normals.base),
            index: TextureIndex.terrainBaseNormal.rawValue
        )
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
            pointLightCount: UInt32(pointLightCount),
            normalMapsEnabled: terrainNormalMapsEnabled ? 1 : 0
        )
        drawUniformBuffer.contents().advanced(by: offset)
            .copyMemory(from: &uniforms, byteCount: MemoryLayout<TerrainDrawUniforms>.size)
        return offset
    }
}
