// CELL water plane encoding, split from RendererScenePass (file-length
// limits; per-pass file pattern like RendererGrassPass). Water renders after
// opaque + cutout geometry with read-only depth and a straight-alpha blend.

import Metal
import simd

extension Renderer {
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

    /// Water renders after opaque + cutout geometry. Depth is read-only;
    /// straight-alpha blend exposes terrain/objects beneath the surface.
    func encodeWater(
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
}
