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
    /// Shader values the mesh animates on its own clock; nil when none move.
    public let animation: MaterialAnimation?

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
        drawState: MaterialDrawState = .standard,
        animation: MaterialAnimation? = nil
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
        self.animation = animation
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

nonisolated extension Material {
    /// The material with every track of `animation` applied at `seconds`.
    public func animated(by animation: MaterialAnimation, at seconds: Float) -> Material {
        var values = AnimatedValues(self)
        for track in animation.tracks {
            guard let value = track.value(at: seconds) else { continue }
            values.set(track.target, value)
        }
        return values.material(from: self)
    }
}

/// The animatable part of a material, edited in place, then written back.
nonisolated private struct AnimatedValues {
    var uvOffset: SIMD2<Float>
    var uvScale: SIMD2<Float>
    var alpha: Float
    var glossiness: Float
    var specularColor: SIMD3<Float>
    var specularStrength: Float
    var effect: EffectShading?
    var shading: SurfaceShading

    init(_ material: Material) {
        uvOffset = material.uvOffset
        uvScale = material.uvScale
        alpha = material.alpha
        glossiness = material.glossiness
        specularColor = material.specularColor
        specularStrength = material.specularStrength
        effect = material.effect
        shading = material.shading
    }

    mutating func set(_ target: MaterialAnimation.Target, _ value: SIMD3<Float>) {
        switch target {
        case .uOffset: uvOffset.x = value.x
        case .vOffset: uvOffset.y = value.x
        case .uScale: uvScale.x = value.x
        case .vScale: uvScale.y = value.x
        case .glossiness: glossiness = value.x
        case .specularStrength: specularStrength = value.x
        case .specularColor: specularColor = value
        case .environmentScale: shading.environmentScale = value.x
        case .refractionStrength: shading.refractionStrength = value.x
        default: setShading(target, value)
        }
    }

    /// Alpha, emissive, and falloff: an effect shape keeps them in its effect shading.
    private mutating func setShading(_ target: MaterialAnimation.Target, _ value: SIMD3<Float>) {
        switch target {
        case .alpha: setAlpha(value.x)
        case .emissiveMultiple: setEmissiveMultiple(value.x)
        case .emissiveColor: setEmissiveColor(value)
        case .falloffStartAngle: setFalloff(0, value.x)
        case .falloffStopAngle: setFalloff(1, value.x)
        case .falloffStartOpacity: setFalloff(2, value.x)
        case .falloffStopOpacity: setFalloff(3, value.x)
        default: return
        }
    }

    /// An effect shape keeps its alpha in the base colour; a lit shape in the material.
    private mutating func setAlpha(_ value: Float) {
        if effect != nil {
            effect?.baseColor.w = value
        } else {
            alpha = value
        }
    }

    private mutating func setEmissiveMultiple(_ value: Float) {
        if effect != nil {
            effect?.baseColorScale = value
        } else {
            shading.emissiveMultiple = value
        }
    }

    private mutating func setEmissiveColor(_ value: SIMD3<Float>) {
        if let base = effect?.baseColor {
            effect?.baseColor = SIMD4(value, base.w)
        } else {
            shading.emissiveColor = value
        }
    }

    private mutating func setFalloff(_ index: Int, _ value: Float) {
        guard effect != nil else { return }
        var falloff = effect?.falloff ?? SIMD4(1, 0, 1, 1)
        falloff[index] = value
        effect?.falloff = falloff
    }

    func material(from base: Material) -> Material {
        Material(
            diffuseTexture: base.diffuseTexture, normalTexture: base.normalTexture,
            uvOffset: uvOffset, uvScale: uvScale, alpha: alpha, glossiness: glossiness,
            specularColor: specularColor, specularStrength: specularStrength,
            doubleSided: base.doubleSided, alphaBlend: base.alphaBlend,
            alphaTestThreshold: base.alphaTestThreshold, additiveBlend: base.additiveBlend,
            effect: effect, waterSurface: base.waterSurface, tintTexture: base.tintTexture,
            tintsSkin: base.tintsSkin, shading: shading, drawState: base.drawState,
            animation: base.animation
        )
    }
}
