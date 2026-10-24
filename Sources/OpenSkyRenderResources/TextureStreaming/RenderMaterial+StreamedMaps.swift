// The maps of a material that texture streaming measures, each with the UV density its
// shader samples it at. See docs/rendering/texture-streaming.md.

import Metal
import OpenSkyShaderTypes

nonisolated extension RenderMaterial {
    /// Matches `landscapeNoiseTile` in MeshShaders.metal: the noise repeats in world space.
    static let landscapeNoiseUVPerUnit: Float = 1 / 4096

    /// Every map a lit draw samples across the surface, paired with its UV per world unit.
    /// A cube map and an effect palette are not sampled by UV, so they are left out.
    public func streamedMaps(uvPerUnit: Float) -> [(texture: MTLTexture, uvPerUnit: Float)] {
        let shared = [
            diffuse, normal, faceTint, surface.glow, surface.environmentMask, surface.backLight
        ]
        var maps = shared.compactMap { $0.map { (texture: $0, uvPerUnit: uvPerUnit) } }
        if let detail = surface.detail {
            let noise = hasTerm(.landscapeNoise)
            maps.append((detail, noise ? Self.landscapeNoiseUVPerUnit : uvPerUnit))
        }
        if let inner = surface.innerLayer {
            // The shader reads the inner layer's alpha at the base UV and its colour scaled.
            let layer = surface.multiLayer
            let scale = hasTerm(.multiLayer) ? max(1, layer.z, layer.w) : 1
            maps.append((inner, uvPerUnit * scale))
        }
        return maps
    }

    private func hasTerm(_ term: ShadingTerm) -> Bool {
        surface.flags & UInt32(term.rawValue) != 0
    }
}
