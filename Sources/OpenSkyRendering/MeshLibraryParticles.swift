// Particle playback construction split from MeshLibrary to keep cache code
// compact. Definitions + textures are shared; every REFR gets fresh sim state.

import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import OpenSkyRenderCore
import OpenSkyRenderResources
import simd

nonisolated extension MeshLibrary {
    nonisolated public func particlePlaybacks(
        path: String,
        surface: ModelSurfaceOverride? = nil,
        placementTransform: float4x4,
        formID: UInt32,
        emittance: EmittanceSource? = nil
    ) throws -> [ParticlePlayback] {
        let pathKey = try meshKey(for: path)
        let key = cacheKey(path: pathKey, terrainLODClipMask: nil, surface: surface)
        guard let definitions = particleDefinitions[key] else { return [] }
        var playbacks: [ParticlePlayback] = []
        for (index, definition) in definitions.enumerated() {
            guard
                definition.maxParticles > 0,
                definition.emitters.contains(where: \.active),
                let shader = definition.effectShader
            else { continue }
            let texture = textures.texture(key: shader.sourceTexturePath, usage: .color)
            let seed = (UInt64(formID) << 32) ^ UInt64(index + 1)
            try playbacks.append(ParticlePlayback(
                device: device,
                definition: definition,
                placementTransform: placementTransform,
                texture: texture,
                effect: RenderEffectMaterial(shading: shader.shading) {
                    textures.texture(key: $0, usage: $1)
                },
                emittance: emittance,
                seed: seed,
                sourcePath: pathKey
            ))
        }
        return playbacks
    }
}
