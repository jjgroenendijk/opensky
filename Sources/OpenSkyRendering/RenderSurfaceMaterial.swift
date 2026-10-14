// The lit-surface textures and constants of one material, ready to bind. An
// absent texture stays nil and its term stays off.

@preconcurrency import Metal
import OpenSkyFormatsCore
import OpenSkyShaderTypes
import simd

nonisolated public struct RenderSurfaceMaterial: Sendable {
    /// ShadingTerm bits.
    public let flags: UInt32
    public let glow: MTLTexture?
    public let detail: MTLTexture?
    public let environment: MTLTexture?
    public let environmentMask: MTLTexture?
    public let innerLayer: MTLTexture?
    public let backLight: MTLTexture?
    public let specular: SIMD4<Float>
    public let emissive: SIMD4<Float>
    public let lightingEffects: SIMD4<Float>
    public let tintColor: SIMD4<Float>
    public let multiLayer: SIMD4<Float>

    public init(material: Material, textureProvider: TextureProvider) {
        let shading = material.shading
        let terms = shading.terms
        func load(_ key: String?, _ usage: TextureUsage) -> MTLTexture? {
            key.map { textureProvider($0, usage) }
        }
        glow = load(shading.glowTexture, .color)
        let height = !terms.isDisjoint(with: [.parallax, .landscapeNoise])
        detail = load(shading.detailTexture, height ? .data : .color)
        environment = load(shading.environmentTexture, .cube)
        environmentMask = load(shading.environmentMaskTexture, .data)
        innerLayer = load(shading.innerLayerTexture, .color)
        let specularMap = terms.contains(.specularMap)
        backLight = load(shading.backLightTexture, specularMap ? .data : .color)
        flags = Self.flags(material: material)
        specular = SIMD4(material.specularColor * material.specularStrength, material.glossiness)
        emissive = SIMD4(shading.emissiveColor, shading.emissiveMultiple)
        lightingEffects = SIMD4(
            shading.lightingEffect1, shading.lightingEffect2, shading.environmentScale,
            shading.refractionStrength
        )
        tintColor = SIMD4(shading.tintColor ?? SIMD3(1, 1, 1), 1)
        let layer = shading.multiLayer
        multiLayer = terms.contains(.sparkle) ? shading.sparkle : SIMD4(
            layer.thickness,
            layer.refractionScale,
            layer.innerScale.x,
            layer.innerScale.y
        )
    }

    public var textures: [MTLTexture] {
        [glow, detail, environment, environmentMask, innerLayer, backLight].compactMap(\.self)
    }

    private static let termBits: [(SurfaceShading.Terms, ShadingTerm)] = [
        (.modelSpaceNormals, .modelSpaceNormals),
        (.specular, .specular),
        (.specularMap, .specularMap),
        (.emissive, .emissive),
        (.glowMap, .glowMap),
        (.softLighting, .softLighting),
        (.rimLighting, .rimLighting),
        (.backLighting, .backLighting),
        (.faceDetail, .faceDetail),
        (.environment, .environment),
        (.environmentMask, .environmentMask),
        (.parallax, .parallax),
        (.multiLayer, .multiLayer),
        (.hairSoftLighting, .hairSoftLighting),
        (.anisotropicLighting, .anisotropicLighting),
        (.environmentLightFade, .environmentLightFade),
        (.externalEmittance, .externalEmittance),
        (.sparkle, .sparkle),
        (.landscapeNoise, .landscapeNoise),
        (.refraction, .refraction),
        (.fireRefraction, .fireRefraction)
    ]

    private static func flags(material: Material) -> UInt32 {
        let terms = material.shading.terms
        var bits = termBits.reduce(UInt32(0)) { bits, pair in
            terms.contains(pair.0) ? bits | UInt32(pair.1.rawValue) : bits
        }
        if material.drawState.screenDoor {
            bits |= UInt32(ShadingTerm.screenDoor.rawValue)
        }
        if material.tintTexture != nil {
            bits |= UInt32(ShadingTerm.faceTint.rawValue)
        }
        if material.normalTexture != nil {
            bits |= UInt32(ShadingTerm.normalMap.rawValue)
        }
        if material.shading.tintColor != nil {
            bits |= UInt32(ShadingTerm.tintColor.rawValue)
            if material.tintsSkin {
                bits |= UInt32(ShadingTerm.skinTint.rawValue)
            }
        }
        return bits
    }
}
