// The GPU side of a material: its textures resolved, its scalars ready for the
// draw uniforms, and its draw state.

import Foundation
@preconcurrency import Metal
import OpenSkyFormatsCore

/// Resolves a material's texture key to a ready MTLTexture. `key` nil means
/// the material has no texture — implementations return a placeholder.
public typealias TextureProvider = (_ key: String?, _ usage: TextureUsage) -> MTLTexture

/// GPU-side material: resolved diffuse texture + the scalar parameters the
/// shader consumes. A blended static shape draws in the blended pass after water.
nonisolated public struct RenderMaterial: Sendable {
    public let diffuse: MTLTexture
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
    public let normal: MTLTexture?
    /// The FaceGen tint the shader overlays on the diffuse; nil on other shapes.
    public let faceTint: MTLTexture?
    public let surface: RenderSurfaceMaterial
    public let drawState: MaterialDrawState

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
    }

    /// Every texture a draw of this material binds, for the residency set.
    public var textures: [MTLTexture] {
        [diffuse] + [normal, faceTint, effect?.palette, effect?.sourceVolume].compactMap(\.self)
            + surface.textures
    }
}
