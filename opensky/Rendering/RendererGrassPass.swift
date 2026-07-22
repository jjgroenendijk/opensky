// Runtime GRAS visibility + instanced draw encoding. Scene build owns model
// loading/grouping; each frame applies user density/distance, frustum culling,
// then a hard upload budget before one indexed draw per surviving group.

import Metal
import simd

extension Renderer {
    private struct GrassInstanceFilter {
        let density: Float
        let maximumDistanceSquared: Float
    }

    func encodeGrass(groups: [GrassDrawGroup], state: inout ScenePassState) {
        var stats = GrassDrawStats(
            sceneInstances: groups.reduce(0) { $0 + $1.instances.count }
        )
        let density = simd_clamp(grassDensityScale, 0, 1)
        let distance = simd_clamp(
            grassDrawDistance,
            GrassRenderPolicy.minimumDrawDistance,
            GrassRenderPolicy.maximumDrawDistance
        )
        guard grassEnabled, density > 0, !groups.isEmpty else {
            stats.densityCulledInstances = stats.sceneInstances
            lastGrassDrawStats = stats
            return
        }

        var remaining = min(
            max(grassInstanceBudget, 0),
            GrassRenderPolicy.maximumInstancesPerFrame
        )
        let filter = GrassInstanceFilter(
            density: density,
            maximumDistanceSquared: distance * distance
        )
        for group in groups {
            encodeGrassGroup(
                group,
                filter: filter,
                remaining: &remaining,
                state: &state,
                stats: &stats
            )
        }
        lastGrassDrawStats = stats
    }

    private func writeGrassInstances(
        _ group: GrassDrawGroup,
        filter: GrassInstanceFilter,
        remaining: inout Int,
        state: inout ScenePassState,
        stats: inout GrassDrawStats
    ) -> (written: Int, base: Int) {
        let base = state.slot * instanceSlotCapacity + state.instanceCursor
        let stride = MemoryLayout<InstanceTransform>.stride
        var written = 0
        for instance in group.instances {
            guard instance.densityKey < filter.density else {
                stats.densityCulledInstances += 1
                continue
            }
            let delta = instance.position - freeFlyCamera.position
            guard simd_length_squared(delta) <= filter.maximumDistanceSquared else {
                stats.distanceCulledInstances += 1
                continue
            }
            if let bounds = instance.bounds, !state.frustum.intersects(bounds) {
                stats.frustumCulledInstances += 1
                state.stats.culledInstances += 1
                continue
            }
            guard remaining > 0 else {
                stats.budgetDroppedInstances += 1
                continue
            }
            writeGrassTransform(instance, at: base + written, stride: stride)
            written += 1
            remaining -= 1
        }
        return (written, base)
    }

    private func encodeGrassGroup(
        _ group: GrassDrawGroup,
        filter: GrassInstanceFilter,
        remaining: inout Int,
        state: inout ScenePassState,
        stats: inout GrassDrawStats
    ) {
        let upload = writeGrassInstances(
            group, filter: filter, remaining: &remaining, state: &state, stats: &stats
        )
        guard upload.written > 0 else { return }
        state.instanceCursor += upload.written
        let uniformOffset = writeGrassUniforms(
            group: group,
            slot: state.slot,
            draw: state.drawCursor
        )
        state.drawCursor += 1
        stats.drawCalls += 1
        stats.drawnInstances += upload.written
        state.stats.drawCalls += 1
        state.stats.drawnInstances += upload.written
        state.encoder.setRenderPipelineState(grassPipeline)
        state.encoder.setCullMode(group.material.doubleSided ? .none : .back)
        argumentTable.setAddress(
            group.mesh.vertexBuffer.gpuAddress,
            index: BufferIndex.vertices.rawValue
        )
        argumentTable.setAddress(
            drawUniformBuffer.gpuAddress + UInt64(uniformOffset),
            index: BufferIndex.drawUniforms.rawValue
        )
        let stride = MemoryLayout<InstanceTransform>.stride
        argumentTable.setAddress(
            instanceTransformBuffer.gpuAddress + UInt64(upload.base * stride),
            index: BufferIndex.instanceTransforms.rawValue
        )
        argumentTable.setTexture(
            group.material.diffuse.gpuResourceID,
            index: TextureIndex.diffuse.rawValue
        )
        state.encoder.drawIndexedPrimitives(
            primitiveType: .triangle,
            indexCount: group.mesh.indexCount,
            indexType: .uint16,
            indexBuffer: group.mesh.indexBuffer.gpuAddress,
            indexBufferLength: group.mesh.indexBuffer.length,
            instanceCount: upload.written
        )
    }

    private func writeGrassTransform(
        _ instance: GrassDrawInstance,
        at index: Int,
        stride: Int
    ) {
        var transform = InstanceTransform(
            modelMatrix: instance.modelMatrix,
            normalMatrix: instance.normalMatrix,
            instanceColor: SIMD4(instance.color, 1),
            grassParameters: SIMD4(instance.wavePeriod, instance.phase, 0, 0)
        )
        instanceTransformBuffer.contents()
            .advanced(by: index * stride)
            .copyMemory(from: &transform, byteCount: MemoryLayout<InstanceTransform>.size)
    }

    private func writeGrassUniforms(
        group: GrassDrawGroup,
        slot: Int,
        draw: Int
    ) -> Int {
        let offset = Self.alignedDrawUniformsSize * (slot * drawUniformSlotCapacity + draw)
        let height = group.mesh.localBounds.max.z - group.mesh.localBounds.min.z
        var uniforms = GrassDrawUniforms(
            uvOffset: group.material.uvOffset,
            uvScale: group.material.uvScale,
            materialAlpha: group.material.alpha,
            alphaThreshold: group.material.alphaTestThreshold ?? 0.5,
            modelMinimumZ: group.mesh.localBounds.min.z,
            inverseModelHeight: height > .ulpOfOne ? 1 / height : 0,
            receivesShadows: 1
        )
        drawUniformBuffer.contents().advanced(by: offset)
            .copyMemory(from: &uniforms, byteCount: MemoryLayout<GrassDrawUniforms>.size)
        return offset
    }
}
