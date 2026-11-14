// The maps of a material that texture streaming measures, each with the UV density its
// shader samples it at. See docs/rendering/texture-streaming.md.

public import Metal
import OpenSkyShaderTypes

nonisolated extension RenderMaterial {
    /// Matches `landscapeNoiseTile` in MeshShaders.metal: the noise repeats in world space.
    static let landscapeNoiseUVPerUnit: Float = 1 / 4096

    /// Every map a lit draw samples across the surface, paired with its UV per world unit.
    /// A cube map and an effect palette are not sampled by UV, so they are left out.
    public func streamedMaps(uvPerUnit: Float) -> [(texture: any MTLTexture, uvPerUnit: Float)] {
        var maps: [(texture: any MTLTexture, uvPerUnit: Float)] = []
        forEachStreamedMap(uvPerUnit: uvPerUnit) { maps.append(($0, $1)) }
        return maps
    }

    /// Calls `body` with each map of `streamedMaps`, in the same order, without
    /// building the list. The streaming pass asks once per drawn instance.
    public func forEachStreamedMap(
        uvPerUnit: Float, _ body: (any MTLTexture, Float) -> Void
    ) {
        let shared = [
            diffuse, normal, faceTint, surface.glow, surface.environmentMask, surface.backLight
        ]
        for case let texture? in shared {
            body(texture, uvPerUnit)
        }
        if let detail = surface.detail {
            let noise = hasTerm(.landscapeNoise)
            body(detail, noise ? Self.landscapeNoiseUVPerUnit : uvPerUnit)
        }
        if let inner = surface.innerLayer {
            // The shader reads the inner layer's alpha at the base UV and its colour scaled.
            let layer = surface.multiLayer
            let scale = hasTerm(.multiLayer) ? max(1, layer.z, layer.w) : 1
            body(inner, uvPerUnit * scale)
        }
    }

    private func hasTerm(_ term: ShadingTerm) -> Bool {
        surface.flags & UInt32(term.rawValue) != 0
    }
}
