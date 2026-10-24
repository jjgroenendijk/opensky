// Billboard particle encoding split from RendererScenePass for file limits.
// Placed and effect systems draw far to near; precipitation follows the camera
// and stays in its own call.

import Metal
import OpenSkyRenderCore
import OpenSkyRenderResources
import OpenSkyShaderTypes

extension Renderer {
    /// Draws each system as one six-vertex instanced billboard call. Depth
    /// tests opaque geometry but never writes, matching effect blend pipelines.
    public func encodeParticles(
        items: [ParticlePlayback],
        enabled: Bool,
        sorted: Bool = false,
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
            let (offset, count) = item.prepareBuffer(
                slot: state.slot, viewer: sorted ? frameInput.view.position : nil
            )
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
                streamedBinding(item.texture),
                index: TextureIndex.diffuse.rawValue
            )
            bindEffect(of: item, state: &state)
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

extension Renderer {
    /// Binds the system's effect uniforms, its palette, and the point lights an
    /// effect-lit system takes. The rings count one draw per system, so a full ring
    /// only happens when a caller skipped `growRings`; the lights then wait.
    private func bindEffect(of item: ParticlePlayback, state: inout ScenePassState) {
        let lit = item.effect.flags & UInt32(EffectFlag.lit.rawValue) != 0
        var lights = PointLightRange()
        if lit, state.drawCursor < drawUniformSlotCapacity {
            lights = writePointLights(near: item.origin, slot: state.slot, draw: state.drawCursor)
            state.drawCursor += 1
        }
        argumentTable.setAddress(
            item.prepareEffect(
                slot: state.slot, pointLightCount: lights.unshadowedCount, regions: regionEmittance
            ),
            index: BufferIndex.drawUniforms.rawValue
        )
        argumentTable.setAddress(
            pointLightBuffer.gpuAddress + UInt64(lights.byteOffset),
            index: BufferIndex.pointLights.rawValue
        )
        argumentTable.setTexture(
            streamedBinding(item.effect.palette ?? item.texture),
            index: TextureIndex.effectPalette.rawValue
        )
    }

    /// Drops the systems whose live particles lie outside the view. Their simulation
    /// still runs, so a system looks the same when it comes back into view.
    func visibleParticles(_ items: [ParticlePlayback], frustum: Frustum) -> [ParticlePlayback] {
        let visible = items.filter { item in
            item.liveBounds.map { frustum.intersects($0) } ?? false
        }
        offscreenParticleSystemCount = items.count - visible.count
        return visible
    }

    /// Far systems first when sorting is on, so near smoke blends over far fire.
    func sortedParticles(_ items: [ParticlePlayback]) -> [ParticlePlayback] {
        guard particleSortingEnabled, items.count > 1 else { return items }
        return ParticleDrawOrder.backToFront(
            items, viewer: frameInput.view.position, at: \.origin
        )
    }
}
