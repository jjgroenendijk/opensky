// Engine-side material, decoupled from NIF block layout (AGENTS.md
// reverse-engineering discipline). Producer: NIF scene flatten
// (NIFFile.model()); consumer: the static-mesh render path,
// which picks sRGB for diffuse and linear for normal maps by usage.

import Foundation
import simd

/// The source factor of an additive blend. Raw values match `DrawUniforms.additiveBlend`.
nonisolated public enum AdditiveBlend: UInt8, Hashable, Sendable {
    /// Source times its alpha, plus the frame.
    case sourceAlpha = 1
    /// Source as it is, plus the frame.
    case one = 2
}

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
    /// Set when the blend adds to the frame (destination factor ONE), such as a glow card.
    public let additiveBlend: AdditiveBlend?
    /// Set for an effect shape: drawn unlit with this shading.
    public let effect: EffectShading?
    /// A water-shader shape: the water pass draws it with the cell's water look.
    public let waterSurface: Bool
    /// The FaceGen face tint, overlay-blended over the diffuse. Nil on other shapes.
    public let tintTexture: String?
    /// A skin-tint shape: the actor's skin colour multiplies its diffuse.
    public let tintsSkin: Bool
    public let shading: SurfaceShading
    public let drawState: MaterialDrawState

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
        additiveBlend: AdditiveBlend? = nil,
        effect: EffectShading? = nil,
        waterSurface: Bool = false,
        tintTexture: String? = nil,
        tintsSkin: Bool = false,
        shading: SurfaceShading = .plain,
        drawState: MaterialDrawState = .standard
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
        self.additiveBlend = additiveBlend
        self.effect = effect
        self.waterSurface = waterSurface
        self.tintTexture = tintTexture
        self.tintsSkin = tintsSkin
        self.shading = shading
        self.drawState = drawState
    }

    /// Neutral stand-in for shapes without a lighting shader: untextured,
    /// opaque, defaults from nif.xml.
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

    /// A `BSWaterShaderProperty` shape. Its look comes from the cell's WATR, not the NIF.
    public static let waterSurface = Material(
        diffuseTexture: nil,
        normalTexture: nil,
        uvOffset: .zero,
        uvScale: SIMD2(1, 1),
        alpha: 1,
        glossiness: 80,
        specularColor: SIMD3(1, 1, 1),
        specularStrength: 0,
        doubleSided: true,
        alphaBlend: true,
        alphaTestThreshold: nil,
        waterSurface: true
    )
}
