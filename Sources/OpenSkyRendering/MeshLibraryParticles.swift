// Particle playback construction split from MeshLibrary to keep cache code
// compact. Definitions + textures are shared; every REFR gets fresh sim state.

import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import OpenSkyGameData
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
            let emits = definition.maxParticles > 0 && definition.emitters.contains(where: \.active)
            guard emits || definition.lightning != nil, let shader = definition.effectShader
            else { continue }
            let texture = textures.texture(key: shader.sourceTexturePath, usage: .color)
            let seed = (UInt64(formID) << 32) ^ UInt64(index + 1)
            try playbacks.append(ParticlePlayback(
                device: device,
                definition: definition,
                placementTransform: placementTransform,
                texture: texture,
                effect: RenderEffectMaterial(shading: shader.shading, source: nil) {
                    textures.texture(key: $0, usage: $1)
                },
                emittance: emittance,
                seed: seed,
                sourcePath: pathKey,
                meshModel: particleMeshModel(pathKey: pathKey, definition: definition, index: index)
            ))
        }
        return playbacks
    }

    /// The meshes a mesh particle system draws per particle; nil for a billboard system
    /// or a pool that does not load, which then draws billboards.
    private func particleMeshModel(
        pathKey: String, definition: ParticleSystemDefinition, index: Int
    ) -> RenderModel? {
        guard definition.meshPool >= 0 else { return nil }
        let key = pathKey + "|particle-mesh:\(index)"
        if let known = particleMeshModels[key] {
            return known
        }
        let model = (try? fileSystem.contents(forPath: pathKey))
            .flatMap { try? NIFFile(data: $0) }
            .flatMap { try? $0.particleMeshModel(pool: definition.meshPool) }
            .flatMap { $0.meshes.isEmpty ? nil : try? makeRenderModel($0, key: key) }
        particleMeshModels[key] = .some(model)
        return model
    }
}
