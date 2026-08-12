// Billboard particle encoding split from RendererScenePass for file limits.

import Metal
import OpenSkyShaderTypes

extension Renderer {
    /// Draws each system as one six-vertex instanced billboard call. Depth
    /// tests opaque geometry but never writes, matching effect blend pipelines.
    func encodeParticles(
        items: [ParticlePlayback],
        enabled: Bool,
        state: inout ScenePassState
    ) {
        // The feature switch ANDed with the view filter: `enabled` is the
        // subsystem's own toggle, `.particles` is the dev shell's layer mask.
        guard enabled, effectiveRenderLayers.contains(.particles), !items.isEmpty else { return }
        state.encoder.setDepthStencilState(waterDepthState)
        // Billboards carry no wire worth drawing, so the wireframe view leaves
        // them filled; the geometry paths after this one get their mode back.
        state.encoder.setTriangleFillMode(.fill)
        defer { state.encoder.setTriangleFillMode(state.fillMode) }
        var boundMode: ParticleBlendMode?
        for item in items {
            let (offset, count) = item.prepareBuffer(slot: state.slot)
            guard count >= 1 else { continue }
            if boundMode != item.blendMode {
                state.encoder.setRenderPipelineState(
                    particlePipelines.pipeline(for: item.blendMode)
                )
                boundMode = item.blendMode
            }
            argumentTable.setAddress(
                item.instanceBuffer.gpuAddress + UInt64(offset),
                index: BufferIndex.particleInstances.rawValue
            )
            argumentTable.setTexture(
                item.texture.gpuResourceID,
                index: TextureIndex.diffuse.rawValue
            )
            state.encoder.setCullMode(.none)
            state.encoder.drawPrimitives(
                primitiveType: .triangle,
                vertexStart: 0,
                vertexCount: 6,
                instanceCount: count
            )
            state.stats.drawCalls += 1
            state.stats.drawnInstances += count
        }
    }
}
