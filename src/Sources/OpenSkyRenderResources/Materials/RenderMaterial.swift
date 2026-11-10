// The GPU side of a material: its textures resolved, its scalars ready for the
// draw uniforms, and its draw state.

import Foundation
@preconcurrency @unsafe public import Metal
public import OpenSkyFormatsCore

/// Resolves a material's texture key to a ready MTLTexture. `key` nil means
/// the material has no texture — implementations return a placeholder.
public typealias TextureProvider = (_ key: String?, _ usage: TextureUsage) -> any MTLTexture

/// GPU-side material: resolved diffuse texture + the scalar parameters the
/// shader consumes. A blended static shape draws in the blended pass after water.
nonisolated public struct RenderMaterial: Sendable {
    public let diffuse: any MTLTexture
    public let uvOffset: SIMD2<Float>
    public let uvScale: SIMD2<Float>
    public let alpha: Float
    /// nil -> opaque pipeline; set -> alpha-test pipeline variant.
    public let alphaTestThreshold: Float?
    /// Render both faces (cull mode none for this draw).
    public let doubleSided: Bool
    public let alphaBlend: Bool
    /// Set for a shape that adds light; it draws with the additive pipelines.
    public let additiveBlend: AdditiveBlend?
    /// Set for an effect shape, which draws unlit.
    public let effect: RenderEffectMaterial?
    /// A water-shader shape: the water pass draws it, not a draw group.
    public let waterSurface: Bool
    public let normal: any MTLTexture?
    /// The FaceGen tint the shader overlays on the diffuse; nil on other shapes.
    public let faceTint: any MTLTexture?
    public let surface: RenderSurfaceMaterial
    public let drawState: MaterialDrawState
    /// The source material, kept only when its shader values animate.
    public let animatedSource: Material?

    public init(material: Material, textureProvider: TextureProvider) {
        diffuse = textureProvider(material.diffuseTexture, .color)
        uvOffset = material.uvOffset
        uvScale = material.uvScale
        alpha = material.alpha
        alphaTestThreshold = material.alphaTestThreshold
        doubleSided = material.doubleSided
        alphaBlend = material.alphaBlend
        additiveBlend = material.additiveBlend
        effect = material.effect.map {
            RenderEffectMaterial(
                shading: $0, source: material.diffuseTexture, textureProvider: textureProvider
            )
        }
        waterSurface = material.waterSurface
        normal = material.normalTexture.map { textureProvider($0, .data) }
        faceTint = material.tintTexture.map { textureProvider($0, .color) }
        surface = RenderSurfaceMaterial(material: material, textureProvider: textureProvider)
        drawState = material.drawState
        animatedSource = material.animation == nil ? nil : material
    }

    /// Every texture a draw of this material binds, for the residency set.
    public var textures: [any MTLTexture] {
        [diffuse] + [normal, faceTint, effect?.palette, effect?.sourceVolume].compactMap(\.self)
            + surface.textures
    }
}

/// The draw uniform values a material animation can change.
nonisolated public struct MaterialScalars: Sendable {
    public var uvOffset: SIMD2<Float>
    public var uvScale: SIMD2<Float>
    public var alpha: Float
    public var effectBaseColor: SIMD4<Float>
    public var effectBaseColorScale: Float
    public var effectFalloff: SIMD4<Float>
    public var specular: SIMD4<Float>
    public var emissive: SIMD4<Float>
}

nonisolated extension RenderMaterial {
    /// The scalars at `seconds` of animation time; the stored values when nothing animates.
    public func scalars(at seconds: Float) -> MaterialScalars {
        guard let source = animatedSource, let animation = source.animation else {
            return MaterialScalars(
                uvOffset: uvOffset, uvScale: uvScale, alpha: alpha,
                effectBaseColor: effect?.baseColor ?? .zero,
                effectBaseColorScale: effect?.baseColorScale ?? 1,
                effectFalloff: effect?.falloff ?? .zero,
                specular: surface.specular, emissive: surface.emissive
            )
        }
        let moved = source.animated(by: animation, at: seconds)
        return MaterialScalars(
            uvOffset: moved.uvOffset, uvScale: moved.uvScale, alpha: moved.alpha,
            effectBaseColor: moved.effect?.baseColor ?? .zero,
            effectBaseColorScale: moved.effect?.baseColorScale ?? 1,
            effectFalloff: moved.effect?.falloff ?? .zero,
            specular: SIMD4(moved.specularColor * moved.specularStrength, moved.glossiness),
            emissive: SIMD4(moved.shading.emissiveColor, moved.shading.emissiveMultiple)
        )
    }
}
