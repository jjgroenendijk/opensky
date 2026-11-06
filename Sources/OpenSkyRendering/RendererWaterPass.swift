// Water surfaces: cell planes and placed water meshes. Water renders after opaque and
// cutout geometry with read-only depth and a straight-alpha blend. To see how deep the
// water is, the scene encoder ends, its depth is copied, and a second encoder draws the
// water over the same targets (docs/rendering/water.md). Soft effects read the same copy.

import Metal
import OpenSkyRenderCore
import OpenSkyRenderResources
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
    /// `bScreenSpaceReflectionEnabled`: the water reflects the scene drawn before it.
    public var screenSpaceReflections = false
    var colorCopy: MTLTexture?
    /// This frame's water reflects the colour copy.
    var reflects = false
    /// This frame copies the colour, for the refraction and the reflection.
    var copiesColour = false

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
        sceneProjection = projection
        let perspective = waterDepth.unproject != nil && !isRenderDebugActive
        waterDepth.waterReads = perspective && waterDepth.enabled && !scene.water.isEmpty
            && effectiveRenderLayers.contains(.water)
        waterDepth.copies = waterDepth.waterReads
            || perspective && (softEffectsInView() || projectedDecalsDraw)
        waterDepth.reflects = waterDepth.waterReads && waterDepth.screenSpaceReflections
        waterDepth.copiesColour = waterDepth.waterReads
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
        let particles = particlesEnabled && effectiveRenderLayers.contains(activeParticleLayer)
            && activeParticles.contains { $0.effect.softDepth > 0 }
        return groups || particles
    }

    private func updateWaterDrawUniforms(
        slot: Int,
        draw: Int,
        item: WaterDrawItem,
        depthBound: Bool,
        bound: (noise: Bool, flow: Bool)
    ) -> Int {
        let offset = Self.alignedDrawUniformsSize * (slot * drawUniformSlotCapacity + draw)
        let look = item.look
        let shading = look.shading
        let rings = waterRipples.live(at: animationTime)
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
            amplitudes: SIMD4(shading.amplitudes, shading.noiseFalloff ?? -1),
            flowVelocity: shading.flowVelocity,
            depthUnproject: waterDepth.unproject ?? .zero,
            detail: SIMD4(
                shading.refractionMagnitude, shading.sunSparkleMagnitude,
                shading.sunSparklePower, bound.noise ? 1 : 0
            ),
            displacement: shading.displacement,
            rings: SIMD4(
                shading.displacementFalloff, frameRainOnWater, Float(rings.count),
                depthBound && waterDepth.copiesColour ? 1 : 0
            ),
            flow: SIMD4(bound.flow ? 1 : 0, shading.flowMapScale, 0, 0),
            ripples: (.zero, .zero, .zero, .zero, .zero, .zero, .zero, .zero)
        )
        WaterRippleField.write(rings, into: &uniforms.ripples)
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
        let noise = waterNoiseTextures?.layers(item.look.shading.noiseTextures)
        if let noise {
            let slots: [TextureIndex] = [.surfaceNormal, .surfaceGlow, .surfaceDetail]
            for (map, index) in zip(noise, slots) {
                argumentTable.setTexture(map.gpuResourceID, index: index.rawValue)
            }
        }
        let flowMapped = bindFlowMaps(item)
        let uniformOffset = updateWaterDrawUniforms(
            slot: state.slot, draw: state.drawCursor, item: item, depthBound: depthBound,
            bound: (noise != nil, flowMapped)
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

    /// Binds the cell's flow map and the flow noise; false while either is missing.
    private func bindFlowMaps(_ item: WaterDrawItem) -> Bool {
        guard
            let path = item.flowMap,
            let flowMap = waterNoiseTextures?.texture(path),
            let flowNoise = waterNoiseTextures?.texture(item.look.shading.flowNoiseTexture)
        else { return false }
        argumentTable.setTexture(flowMap.gpuResourceID, index: TextureIndex.waterFlowMap.rawValue)
        argumentTable.setTexture(
            flowNoise.gpuResourceID, index: TextureIndex.waterFlowNoise.rawValue
        )
        return true
    }

    /// Ends the scene encoder, copies its depth, and opens a second encoder on the same
    /// color and depth with the copy bound.
    private func splitForSceneDepth(
        descriptor: MTL4RenderPassDescriptor,
        state: ScenePassState,
        frameOffset: Int
    ) -> ScenePassState? {
        guard
            let depth = descriptor.depthAttachment.texture,
            let colour = descriptor.colorAttachments[0].texture
        else {
            state.encoder.endEncoding()
            return nil
        }
        var copies = [ScenePassCopy(source: depth, target: \.waterDepth.copy, label: "Water")]
        if waterDepth.copiesColour {
            copies.append(
                ScenePassCopy(source: colour, target: \.waterDepth.colorCopy, label: "Water")
            )
        }
        let split = splitScenePass(
            descriptor: descriptor, state: state, frameOffset: frameOffset, copies: copies
        )
        if let copy = waterDepth.copy {
            argumentTable.setTexture(copy.gpuResourceID, index: TextureIndex.sceneDepth.rawValue)
        }
        if waterDepth.copiesColour, let colorCopy = waterDepth.colorCopy {
            argumentTable.setTexture(
                colorCopy.gpuResourceID, index: TextureIndex.sceneColor.rawValue
            )
        }
        return split
    }
}
