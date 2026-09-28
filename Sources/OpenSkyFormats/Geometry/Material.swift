// Engine-side material, decoupled from NIF block layout (AGENTS.md
// reverse-engineering discipline). Producer: NIF scene flatten
// (NIFFile.model(), todo 2.4); consumer: the static-mesh render path (2.6),
// which picks sRGB for diffuse and linear for normal maps by usage.

import Foundation
import simd

nonisolated package struct Material: Hashable {
    /// Normalized VFS key ("textures/….dds"); nil = no texture.
    package let diffuseTexture: String?
    package let normalTexture: String?
    package let uvOffset: SIMD2<Float>
    package let uvScale: SIMD2<Float>
    /// Material opacity, 1 = opaque.
    package let alpha: Float
    /// Specular power.
    package let glossiness: Float
    package let specularColor: SIMD3<Float>
    package let specularStrength: Float
    /// Render both faces (cull mode none).
    package let doubleSided: Bool
    /// Alpha blending on (NiAlphaProperty blend bit).
    package let alphaBlend: Bool
    /// Alpha-test cutoff in [0, 1]; nil = no test. Foliage cutouts set this.
    package let alphaTestThreshold: Float?

    package init(
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
        alphaTestThreshold: Float?
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
    }

    /// Neutral stand-in for shapes without a lighting shader (effect, water
    /// and sky shaders are out of M2 scope): untextured, opaque, defaults
    /// from nif.xml.
    package static let fallback = Material(
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
