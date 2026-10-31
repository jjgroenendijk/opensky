// The GPU half of `EffectShading`: the resolved palette texture and the values
// the static-mesh fragment reads from `DrawUniforms`.

@preconcurrency import Metal
import OpenSkyFormatsCore
import OpenSkyShaderTypes
import simd

nonisolated public struct RenderEffectMaterial: Sendable {
    /// Nil when the shape names no palette; the diffuse is bound in its place.
    public let palette: MTLTexture?
    /// The source texture when its file is a volume; the diffuse then holds a placeholder.
    public let sourceVolume: MTLTexture?
    /// `EffectFlag` bits.
    public private(set) var flags: UInt32
    public let baseColor: SIMD4<Float>
    public let baseColorScale: Float
    public let falloff: SIMD4<Float>
    public let softDepth: Float
    public let lightingInfluence: Float
    /// Drawn only on a bloody weapon (`Renderer.encodeWeaponBlood`).
    public let weaponBlood: Bool

    /// `source` is the shape's source texture key, which may name a volume.
    public init(shading: EffectShading, source: String?, textureProvider: TextureProvider) {
        // A palette flag with no palette path would sample the placeholder, so
        // such a shape keeps its texture colors instead.
        let hasPalette = shading.paletteTexture != nil
        let resolved = source.map { textureProvider($0, .effectSource) }
        self.init(
            shading: shading,
            palette: hasPalette && (shading.paletteColor || shading.paletteAlpha)
                ? textureProvider(shading.paletteTexture, .color) : nil,
            sourceVolume: resolved?.textureType == .type3D ? resolved : nil
        )
    }

    /// `palette` is the resolved palette texture, nil when the shading uses none.
    public init(shading: EffectShading, palette: MTLTexture?, sourceVolume: MTLTexture? = nil) {
        self.palette = palette
        self.sourceVolume = sourceVolume
        flags = Self.flags(shading, hasPalette: palette != nil)
        if sourceVolume != nil {
            flags |= UInt32(EffectFlag.sourceVolume.rawValue)
        }
        baseColor = shading.baseColor
        baseColorScale = shading.baseColorScale
        falloff = shading.falloff ?? .zero
        softDepth = shading.softFalloffDepth ?? 0
        lightingInfluence = shading.lightingInfluence ?? 0
        weaponBlood = shading.weaponBlood
    }

    /// Particles with no effect shader, such as generated rain: the particle colour only.
    public static let plainParticles = RenderEffectMaterial(
        shading: EffectShading(
            baseColor: SIMD4(repeating: 1), baseColorScale: 1, paletteTexture: nil,
            paletteColor: false, paletteAlpha: false, falloff: nil, vertexColors: true,
            vertexAlpha: true
        ),
        palette: nil
    )

    /// `material` with the vertex colour and alpha flags on, for particle colours.
    public static func forParticles(_ material: RenderEffectMaterial) -> RenderEffectMaterial {
        var copy = material
        copy.flags |= UInt32(EffectFlag.vertexColors.rawValue | EffectFlag.vertexAlpha.rawValue)
        return copy
    }

    /// `EffectFlag` bits; a palette flag needs a palette to sample.
    public static func flags(_ shading: EffectShading, hasPalette: Bool) -> UInt32 {
        let bits: [(Bool, EffectFlag)] = [
            (true, .enabled),
            (hasPalette && shading.paletteColor, .paletteColor),
            (hasPalette && shading.paletteAlpha, .paletteAlpha),
            (shading.falloff != nil, .falloff),
            (shading.vertexColors, .vertexColors),
            (shading.vertexAlpha, .vertexAlpha),
            ((shading.softFalloffDepth ?? 0) > 0, .soft),
            (shading.lightingInfluence != nil, .lit),
            (shading.externalEmittance, .externalEmittance)
        ]
        return bits.reduce(0) { $0 | ($1.0 ? UInt32($1.1.rawValue) : 0) }
    }
}
