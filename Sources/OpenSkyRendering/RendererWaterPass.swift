// Water surfaces: cell planes and placed water meshes. Water renders after opaque and
// cutout geometry with read-only depth and a straight-alpha blend. To see how deep the
// water is, the scene encoder ends, its depth is copied, and a second encoder draws the
// water over the same targets (docs/rendering/water.md).

import Metal
import OpenSkyShaderTypes
import simd

/// The scene depth copy the water reads, and whether the split runs at all.
public struct WaterDepthState {
    /// Off draws the water in the scene encoder with a fixed middle depth.
    public var enabled = true
    var copy: MTLTexture?
    /// Projection terms of this frame; nil when the projection is not a perspective one.
    var unproject: SIMD2<Float>?

    public init() {}

    /// (m22, m32) of a right-handed perspective projection; Metal depth runs 0...1.
    nonisolated static func unproject(_ projection: float4x4) -> SIMD2<Float>? {
        guard projection.columns.2.w == -1, projection.columns.3.w == 0 else { return nil }
        return SIMD2(projection.columns.2.z, projection.columns.3.z)
    }
}

extension Renderer {
    /// True when this frame's water reads the scene depth, so the pass must store it.
    func waterReadsDepth(projection: float4x4) -> Bool {
        waterDepth.unproject = WaterDepthState.unproject(projection)
        return waterDepth.enabled && waterDepth.unproject != nil && !scene.water.isEmpty
            && effectiveRenderLayers.contains(.water) && !isRenderDebugActive
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

    /// Draws every water item. With `descriptor`, the pass first splits so the
    /// water can read the depth drawn so far. False when the split cannot open
    /// its second encoder; the frame is then dropped.
    func encodeWater(
        items: [WaterDrawItem],
        depthFrom descriptor: MTL4RenderPassDescriptor?,
        frameOffset: Int,
        state: inout ScenePassState
    ) -> Bool {
        guard !items.isEmpty, effectiveRenderLayers.contains(.water) else { return true }
        var depthBound = false
        if let descriptor {
            guard
                let split = splitForWaterDepth(
                    descriptor: descriptor, state: state, frameOffset: frameOffset
                )
            else { return false }
            state = split
            depthBound = true
        }
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
        return true
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
    private func splitForWaterDepth(
        descriptor: MTL4RenderPassDescriptor,
        state: ScenePassState,
        frameOffset: Int
    ) -> ScenePassState? {
        state.encoder.endEncoding()
        guard
            let depth = descriptor.depthAttachment.texture,
            let copy = waterDepthCopy(matching: depth),
            let blit = commandBuffer.makeComputeCommandEncoder()
        else { return nil }
        blit.label = "WaterDepthCopy"
        blit.barrier(afterQueueStages: .fragment, beforeStages: .blit, visibilityOptions: .device)
        blit.copy(sourceTexture: depth, destinationTexture: copy)
        blit.barrier(afterStages: .blit, beforeQueueStages: .fragment, visibilityOptions: .device)
        blit.endEncoding()
        guard
            let encoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: Self.continuingDescriptor(after: descriptor)
            )
        else { return nil }
        bindScenePassFrameArguments(encoder: encoder, frameOffset: frameOffset)
        encoder.label = "Water"
        encoder.setTriangleFillMode(state.fillMode)
        argumentTable.setTexture(copy.gpuResourceID, index: TextureIndex.waterDepth.rawValue)
        var next = ScenePassState(encoder: encoder, slot: state.slot, frustum: state.frustum)
        next.fillMode = state.fillMode
        next.drawCursor = state.drawCursor
        next.instanceCursor = state.instanceCursor
        next.stats = state.stats
        return next
    }

    private func waterDepthCopy(matching depth: MTLTexture) -> MTLTexture? {
        if
            let copy = waterDepth.copy, copy.width == depth.width, copy.height == depth.height,
            copy.pixelFormat == depth.pixelFormat
        {
            return copy
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: depth.pixelFormat, width: depth.width, height: depth.height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "WaterDepthCopy"
        if let old = waterDepth.copy {
            residencySet.removeAllocation(old)
        }
        residencySet.addAllocation(texture)
        residencySet.commit()
        waterDepth.copy = texture
        return texture
    }

    /// The same targets, loading the color and depth drawn so far and keeping both.
    private static func continuingDescriptor(
        after descriptor: MTL4RenderPassDescriptor
    ) -> MTL4RenderPassDescriptor {
        let next = MTL4RenderPassDescriptor()
        next.colorAttachments[0].texture = descriptor.colorAttachments[0].texture
        next.colorAttachments[0].loadAction = .load
        next.colorAttachments[0].storeAction = .store
        next.depthAttachment.texture = descriptor.depthAttachment.texture
        next.depthAttachment.loadAction = .load
        next.depthAttachment.storeAction = .store
        next.stencilAttachment.texture = descriptor.stencilAttachment.texture
        next.stencilAttachment.loadAction = .clear
        next.stencilAttachment.storeAction = .dontCare
        next.stencilAttachment.clearStencil = 0
        return next
    }
}
