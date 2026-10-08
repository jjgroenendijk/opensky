// The GPU half of `EffectShading`: the resolved palette texture and the values
// the static-mesh fragment reads from `DrawUniforms`.

@preconcurrency import Metal
import OpenSkyFormatsCore
import OpenSkyShaderTypes
import simd

nonisolated public struct RenderEffectMaterial: Sendable {
    /// Nil when the shape names no palette; the diffuse is bound in its place.
    public let palette: MTLTexture?
    /// `EffectFlag` bits.
    public let flags: UInt32
    public let baseColor: SIMD4<Float>
    public let baseColorScale: Float
    public let falloff: SIMD4<Float>

    public init(shading: EffectShading, textureProvider: TextureProvider) {
        // A palette flag with no palette path would sample the placeholder, so
        // such a shape keeps its texture colors instead.
        let hasPalette = shading.paletteTexture != nil
        palette = hasPalette && (shading.paletteColor || shading.paletteAlpha)
            ? textureProvider(shading.paletteTexture, .color) : nil
        let bits: [(Bool, EffectFlag)] = [
            (true, .enabled),
            (hasPalette && shading.paletteColor, .paletteColor),
            (hasPalette && shading.paletteAlpha, .paletteAlpha),
            (shading.falloff != nil, .falloff),
            (shading.vertexColors, .vertexColors),
            (shading.vertexAlpha, .vertexAlpha)
        ]
        flags = bits.reduce(0) { $0 | ($1.0 ? UInt32($1.1.rawValue) : 0) }
        baseColor = shading.baseColor
        baseColorScale = shading.baseColorScale
        falloff = shading.falloff ?? .zero
    }
}
