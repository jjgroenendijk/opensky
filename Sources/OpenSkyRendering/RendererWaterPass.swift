// Water surfaces: cell planes and placed water meshes. Water renders after opaque and
// cutout geometry with read-only depth and a straight-alpha blend. To see how deep the
// water is, the scene encoder ends, its depth is copied, and a second encoder draws the
// water over the same targets (docs/rendering/water.md). Soft effects read the same copy.

import Metal
import OpenSkyShaderTypes
import simd

/// The scene depth copy the water and the soft effects read, and whether the split runs.
public struct WaterDepthState {
    /// Off draws the water in the scene encoder with a fixed middle depth.
    public var enabled = true
    var copy: MTLTexture?
    /// Projection terms of this frame; nil when the projection is not a perspective one.
    var unproject: SIMD2<Float>?
    /// This frame's water reads the copy.
    var waterReads = false
    /// This frame copies the depth, for the water or for a soft effect in view.
    var copies = false

    public init() {}

    /// (m22, m32) of a right-handed perspective projection; Metal depth runs 0...1.
    nonisolated static func unproject(_ projection: float4x4) -> SIMD2<Float>? {
        guard projection.columns.2.w == -1, projection.columns.3.w == 0 else { return nil }
        return SIMD2(projection.columns.2.z, projection.columns.3.z)
    }
}

extension Renderer {
    /// Decides whether this frame copies the scene depth, so the pass must store it.
    /// Runs before the frame uniforms, which tell the shaders whether the copy is bound.
    func planSceneDepthCopy(projection: float4x4) {
        waterDepth.unproject = WaterDepthState.unproject(projection)
        let perspective = waterDepth.unproject != nil && !isRenderDebugActive
        waterDepth.waterReads = perspective && waterDepth.enabled && !scene.water.isEmpty
            && effectiveRenderLayers.contains(.water)
        waterDepth.copies = waterDepth.waterReads || perspective && softEffectsInView()
    }

    /// `FrameUniforms.sceneDepthUnproject`.
    var sceneDepthUnproject: SIMD4<Float> {
        let terms = waterDepth.unproject ?? .zero
        return SIMD4(terms.x, terms.y, waterDepth.copies ? 1 : 0, 0)
    }

    private func softEffectsInView() -> Bool {
        guard shadingTerms.contains(.softEffects) else { return false }
        let soft = UInt32(EffectFlag.soft.rawValue)
        let groups = frameDrawGroups.alphaTested.contains {
            $0.drawsBlended && ($0.material.effect?.flags ?? 0) & soft != 0
        }
        let particles = particlesEnabled && effectiveRenderLayers.contains(.particles)
            && (scene.particles + effects.particles).contains { $0.effect.softDepth > 0 }
        return groups || particles
    }

    private func updateWaterDrawUniforms(
        slot: Int,
        draw: Int,
        item: WaterDrawItem,
        depthBound: Bool
    ) -> Int {
        let offset = Self.alignedDrawUniformsSize * (slot * drawUniformSlotCapacity + draw)
        let look = item.look
        let shading = look.shading
        var uniforms = WaterDrawUniforms(
            modelMatrix: item.modelMatrix,
            shallowColor: look.shallowColor,
            deepColor: look.deepColor,
            reflectionColor: look.reflectionColor,
            surface: SIMD4(
                shading.opacity, shading.fresnelAmount, shading.reflectivity,
                shading.sunSpecularPower
            ),
            depthAndSun: SIMD4(
                shading.sunSpecularMagnitude, shading.fogNear, shading.fogFar,
                depthBound ? 1 : 0
            ),
            windDirections: SIMD4(shading.windDirections * (.pi / 180), 0),
            windSpeeds: SIMD4(shading.windSpeeds, 0),
            uvScales: SIMD4(shading.uvScales, 0),
            amplitudes: SIMD4(shading.amplitudes, 0),
            flowVelocity: shading.flowVelocity,
            depthUnproject: waterDepth.unproject ?? .zero
        )
        drawUniformBuffer.contents().advanced(by: offset)
            .copyMemory(from: &uniforms, byteCount: MemoryLayout<WaterDrawUniforms>.size)
        return offset
    }

    /// When this frame copies the scene depth, splits the pass so the water and the
    /// blended effects after it can read the depth drawn so far. False when the split
    /// cannot open its second encoder; the frame is then dropped.
    func copySceneDepth(
        descriptor: MTL4RenderPassDescriptor,
        frameOffset: Int,
        state: inout ScenePassState
    ) -> Bool {
        guard waterDepth.copies else { return true }
        guard
            let split = splitForSceneDepth(
                descriptor: descriptor, state: state, frameOffset: frameOffset
            )
        else { return false }
        state = split
        return true
    }

    /// Draws every water item, reading the scene depth copy when the frame made one.
    func encodeWater(items: [WaterDrawItem], state: inout ScenePassState) {
        guard !items.isEmpty, effectiveRenderLayers.contains(.water) else { return }
        let depthBound = waterDepth.waterReads
        state.encoder.setRenderPipelineState(
            isRenderDebugActive ? debugPipelines.water : waterPipeline
        )
        state.encoder.setDepthStencilState(waterDepthState)
        for item in items {
            if let bounds = item.bounds, !state.frustum.intersects(bounds) {
                state.stats.culledInstances += 1
                continue
            }
            encodeWaterItem(item, depthBound: depthBound, state: &state)
        }
        state.encoder.setDepthStencilState(depthState)
    }

    private func encodeWaterItem(
        _ item: WaterDrawItem,
        depthBound: Bool,
        state: inout ScenePassState
    ) {
        let uniformOffset = updateWaterDrawUniforms(
            slot: state.slot, draw: state.drawCursor, item: item, depthBound: depthBound
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

    /// Ends the scene encoder, copies its depth, and opens a second encoder on the same
    /// color and depth with the copy bound.
    private func splitForSceneDepth(
        descriptor: MTL4RenderPassDescriptor,
        state: ScenePassState,
        frameOffset: Int
    ) -> ScenePassState? {
        guard let depth = descriptor.depthAttachment.texture else {
            state.encoder.endEncoding()
            return nil
        }
        let split = splitScenePass(
            descriptor: descriptor, state: state, frameOffset: frameOffset,
            copy: ScenePassCopy(source: depth, target: \.waterDepth.copy, label: "Water")
        )
        if let copy = waterDepth.copy {
            argumentTable.setTexture(copy.gpuResourceID, index: TextureIndex.sceneDepth.rawValue)
        }
        return split
    }
}
