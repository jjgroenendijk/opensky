// Particle playback construction split from MeshLibrary to keep cache code
// compact. Definitions + textures are shared; every REFR gets fresh sim state.

import simd

extension MeshLibrary {
    nonisolated func particlePlaybacks(
        path: String,
        placementTransform: float4x4,
        formID: UInt32
    ) throws -> [ParticlePlayback] {
        let pathKey = try meshKey(for: path)
        let key = cacheKey(path: pathKey, terrainLODClipMask: nil)
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
                seed: seed,
                sourcePath: pathKey
            ))
        }
        return playbacks
    }
}
