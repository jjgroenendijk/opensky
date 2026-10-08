// The unlit shading of an effect shape: stream foam, waterfalls, mist cards.
// Producer: the NIF flatten, from BSEffectShaderProperty; layout and flags in
// docs/formats/nif-materials.md. Consumer: the static-mesh fragment shader.

import Foundation
import simd

nonisolated public struct EffectShading: Hashable, Sendable {
    /// Emissive color with alpha; multiplies the texture.
    public let baseColor: SIMD4<Float>
    /// RGB multiplier applied last.
    public let baseColorScale: Float
    /// Normalized VFS key of the greyscale palette; nil = none.
    public let paletteTexture: String?
    /// RGB comes from the palette, indexed by the texture's green channel.
    public let paletteColor: Bool
    /// Alpha comes from the palette, indexed by the texture's alpha channel.
    public let paletteAlpha: Bool
    /// Start and stop cosines, then start and stop opacity; nil = no falloff.
    public let falloff: SIMD4<Float>?
    public let vertexColors: Bool
    public let vertexAlpha: Bool

    public init(
        baseColor: SIMD4<Float>,
        baseColorScale: Float,
        paletteTexture: String?,
        paletteColor: Bool,
        paletteAlpha: Bool,
        falloff: SIMD4<Float>?,
        vertexColors: Bool,
        vertexAlpha: Bool
    ) {
        self.baseColor = baseColor
        self.baseColorScale = baseColorScale
        self.paletteTexture = paletteTexture
        self.paletteColor = paletteColor
        self.paletteAlpha = paletteAlpha
        self.falloff = falloff
        self.vertexColors = vertexColors
        self.vertexAlpha = vertexAlpha
    }
}
