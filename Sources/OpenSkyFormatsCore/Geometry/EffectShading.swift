// The unlit shading of an effect shape: stream foam, waterfalls, mist cards.
// Producer: the NIF flatten, from BSEffectShaderProperty; layout and flags in
// docs/formats/nif-materials.md. Consumer: the static-mesh fragment shader.

import Foundation
import simd

nonisolated public struct EffectShading: Hashable, Sendable {
    /// Emissive color with alpha; multiplies the texture.
    public var baseColor: SIMD4<Float>
    /// RGB multiplier applied last.
    public var baseColorScale: Float
    /// Normalized VFS key of the greyscale palette; nil = none.
    public var paletteTexture: String?
    /// RGB comes from the palette, indexed by the texture's green channel.
    public var paletteColor: Bool
    /// Alpha comes from the palette, indexed by the texture's alpha channel.
    public var paletteAlpha: Bool
    /// Start and stop cosines, then start and stop opacity; nil = no falloff.
    public var falloff: SIMD4<Float>?
    public var vertexColors: Bool
    public var vertexAlpha: Bool
    /// Depth in world units over which the shape fades in where it meets the scene; nil = hard.
    public var softFalloffDepth: Float?
    /// Share of the scene light the shape takes, 0 to 1; nil = unlit.
    public var lightingInfluence: Float?
    /// The placed reference's emittance colour stands in for the scene light.
    public var externalEmittance: Bool
    /// Blood on a weapon: hidden until the weapon hits a bleeding actor.
    public var weaponBlood: Bool

    public init(
        baseColor: SIMD4<Float>,
        baseColorScale: Float,
        paletteTexture: String?,
        paletteColor: Bool,
        paletteAlpha: Bool,
        falloff: SIMD4<Float>?,
        vertexColors: Bool,
        vertexAlpha: Bool,
        softFalloffDepth: Float? = nil,
        lightingInfluence: Float? = nil,
        externalEmittance: Bool = false,
        weaponBlood: Bool = false
    ) {
        self.baseColor = baseColor
        self.baseColorScale = baseColorScale
        self.paletteTexture = paletteTexture
        self.paletteColor = paletteColor
        self.paletteAlpha = paletteAlpha
        self.falloff = falloff
        self.vertexColors = vertexColors
        self.vertexAlpha = vertexAlpha
        self.softFalloffDepth = softFalloffDepth
        self.lightingInfluence = lightingInfluence
        self.externalEmittance = externalEmittance
        self.weaponBlood = weaponBlood
    }
}
