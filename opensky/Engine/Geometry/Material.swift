// Engine-side material, decoupled from NIF block layout (AGENTS.md
// reverse-engineering discipline). Producer: NIF scene flatten
// (NIFFile.model(), todo 2.4); consumer: the static-mesh render path (2.6),
// which picks sRGB for diffuse and linear for normal maps by usage.

import Foundation
import simd

nonisolated struct Material: Hashable {
    /// Normalized VFS key ("textures/….dds"); nil = no texture.
    let diffuseTexture: String?
    let normalTexture: String?
    let uvOffset: SIMD2<Float>
    let uvScale: SIMD2<Float>
    /// Material opacity, 1 = opaque.
    let alpha: Float
    /// Specular power.
    let glossiness: Float
    let specularColor: SIMD3<Float>
    let specularStrength: Float
    /// Render both faces (cull mode none).
    let doubleSided: Bool
    /// Alpha blending on (NiAlphaProperty blend bit).
    let alphaBlend: Bool
    /// Alpha-test cutoff in [0, 1]; nil = no test. Foliage cutouts set this.
    let alphaTestThreshold: Float?

    /// Neutral stand-in for shapes without a lighting shader (effect, water
    /// and sky shaders are out of M2 scope): untextured, opaque, defaults
    /// from nif.xml.
    static let fallback = Material(
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
