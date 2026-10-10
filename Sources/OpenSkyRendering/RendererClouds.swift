// Draws the weather's cloud layers over the sky gradient, each on its dome shape.

import Metal
import OpenSkyShaderTypes
import simd

extension Renderer {
    /// The layers this frame draws: exterior weather only, and only under a sky.
    var frameCloudLayers: [ResolvedCloudLayer] {
        guard cloudsEnabled, scene.sky != nil, scene.lighting == nil else { return [] }
        return currentResolvedWeather?.clouds ?? []
    }

    /// Drains finished cloud loads and requests the layers the weather needs now.
    public func prepareClouds() {
        guard let skyClouds else { return }
        let added = skyClouds.prepare(frameCloudLayers)
        guard !added.isEmpty else { return }
        residencySet.addAllocations(added)
        residencySet.commit()
    }

    func encodeClouds(state: inout ScenePassState) {
        guard let skyClouds, let dome = skyClouds.dome else { return }
        let layers = frameCloudLayers.filter { $0.alpha > 0.001 }
        var drawn = 0
        state.encoder.setRenderPipelineState(cloudPipeline)
        argumentTable.setAddress(dome.vertices.gpuAddress, index: BufferIndex.vertices.rawValue)
        for layer in layers where drawn < SkyClouds.maximumDraws {
            guard
                dome.shapes.indices.contains(layer.layer),
                let texture = skyClouds.texture(layer.texture)
            else { continue }
            let offset = SkyClouds.uniformStride
                * (state.slot * SkyClouds.maximumDraws + drawn)
            var uniforms = CloudLayerUniforms(
                colorAlpha: SIMD4(layer.color, layer.alpha),
                uvOffset: Self.cloudOffset(layer.velocity, seconds: animationTime),
                padding: .zero
            )
            skyClouds.uniforms.contents().advanced(by: offset)
                .copyMemory(from: &uniforms, byteCount: MemoryLayout<CloudLayerUniforms>.size)
            argumentTable.setAddress(
                skyClouds.uniforms.gpuAddress + UInt64(offset),
                index: BufferIndex.drawUniforms.rawValue
            )
            argumentTable.setTexture(texture.gpuResourceID, index: TextureIndex.diffuse.rawValue)
            let shape = dome.shapes[layer.layer]
            let stride = MemoryLayout<UInt32>.stride
            state.encoder.drawIndexedPrimitives(
                primitiveType: .triangle,
                indexCount: shape.count,
                indexType: .uint32,
                indexBuffer: dome.indices.gpuAddress + UInt64(shape.lowerBound * stride),
                indexBufferLength: shape.count * stride
            )
            drawn += 1
            state.stats.drawCalls += 1
        }
        skyClouds.drawnLayerCount = drawn
    }

    /// Wrapped to one texture repeat, so a long session keeps float precision.
    nonisolated static func cloudOffset(_ velocity: SIMD2<Float>, seconds: Float) -> SIMD2<Float> {
        let moved = velocity * seconds
        return moved - moved.rounded(.down)
    }
}

extension Renderer {
    /// The sidebar's cloud line.
    public var cloudReadout: String {
        guard cloudsEnabled else { return "off" }
        guard let skyClouds else { return "no game data" }
        if let failure = skyClouds.failedPaths.last {
            return "failed \(failure)"
        }
        guard skyClouds.dome != nil else { return "loading \(SkyClouds.domePath)" }
        let wanted = frameCloudLayers.filter { $0.alpha > 0.001 }.count
        return "\(skyClouds.drawnLayerCount) of \(wanted) layers"
    }
}
