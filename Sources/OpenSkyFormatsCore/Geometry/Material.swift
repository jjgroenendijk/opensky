// Engine-side material, decoupled from NIF block layout (AGENTS.md
// reverse-engineering discipline). Producer: NIF scene flatten
// (NIFFile.model()); consumer: the static-mesh render path,
// which picks sRGB for diffuse and linear for normal maps by usage.

import Foundation
import simd

nonisolated public struct Material: Hashable, Sendable {
    /// Normalized VFS key ("textures/….dds"); nil = no texture.
    public let diffuseTexture: String?
    public let normalTexture: String?
    public let uvOffset: SIMD2<Float>
    public let uvScale: SIMD2<Float>
    /// Material opacity, 1 = opaque.
    public let alpha: Float
    /// Specular power.
    public let glossiness: Float
    public let specularColor: SIMD3<Float>
    public let specularStrength: Float
    /// Render both faces (cull mode none).
    public let doubleSided: Bool
    /// Alpha blending on (NiAlphaProperty blend bit).
    public let alphaBlend: Bool
    /// Alpha-test cutoff in [0, 1]; nil = no test. Foliage cutouts set this.
    public let alphaTestThreshold: Float?
    /// Set for an effect shape: drawn unlit with this shading.
    public let effect: EffectShading?

    public init(
        diffuseTexture: String?,
        normalTexture: String?,
        uvOffset: SIMD2<Float>,
        uvScale: SIMD2<Float>,
        alpha: Float,
        glossiness: Float,
        specularColor: SIMD3<Float>,
        specularStrength: Float,
        doubleSided: Bool,
        alphaBlend: Bool,
        alphaTestThreshold: Float?,
        effect: EffectShading? = nil
    ) {
        self.diffuseTexture = diffuseTexture
        self.normalTexture = normalTexture
        self.uvOffset = uvOffset
        self.uvScale = uvScale
        self.alpha = alpha
        self.glossiness = glossiness
        self.specularColor = specularColor
        self.specularStrength = specularStrength
        self.doubleSided = doubleSided
        self.alphaBlend = alphaBlend
        self.alphaTestThreshold = alphaTestThreshold
        self.effect = effect
    }

    /// Neutral stand-in for shapes without a lighting shader (effect, water,
    /// and sky shaders have their own paths): untextured, opaque, defaults
    /// from nif.xml.
    public static let fallback = Material(
        diffuseTexture: nil,
        normalTexture: nil,
        uvOffset: .zero,
        uvScale: SIMD2(1, 1),
        alpha: 1,
        glossiness: 80,
        specularColor: SIMD3(1, 1, 1),
        specularStrength: 1,
        doubleSided: false,
        alphaBlend: false,
        alphaTestThreshold: nil
    )
}
