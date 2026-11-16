// Which shader type, flag, and texture slot turn on each lit-surface term. The
// rules follow NifSkope's open renderer: docs/formats/nif-materials.md.

import Foundation
import OpenSkyFormatsCore

nonisolated extension NIFLightingShaderProperty {
    private typealias ShaderType = NIFLightingShaderType

    /// A term whose texture slot is empty stays off.
    func surfaceShading(textures: NIFShaderTextureSet?) -> SurfaceShading {
        var shading = parameters()
        let slot = { (index: Int) in textures?.path(slot: index) }
        let modelSpace = has(.modelSpaceNormals)
        let backLight = has(.backLighting) ? slot(7) : nil
        let specularMap = has(.specular) && modelSpace && backLight == nil ? slot(7) : nil
        shading.backLightTexture = backLight ?? specularMap
        let lightMask = has(.softLighting) || has(.rimLighting) ? slot(2) : nil
        let glow = shaderType == ShaderType.glow && has(.glowMap) ? slot(2) : nil
        shading.glowTexture = glow ?? lightMask
        let detail = shaderType == ShaderType.faceGen && has(.faceGenDetailMap) ? slot(3) : nil
        let height = shaderType == ShaderType.parallax && has(.parallax) ? slot(3) : nil
        let noise = shaderType == ShaderType.lodLandscapeNoise ? Self.landscapeNoise : nil
        shading.detailTexture = detail ?? height ?? noise
        let multiLayer = shaderType == ShaderType.multiLayer && has(.multiLayerParallax)
            ? slot(6) : nil
        shading.innerLayerTexture = multiLayer
        let environment = hasEnvironment(multiLayer: multiLayer != nil) ? slot(4) : nil
        shading.environmentTexture = environment
        shading.environmentMaskTexture = environment != nil ? slot(5) : nil
        let sparkle = Self.hasSparkleVector(shaderType) && has(.projectedUV) && has(.multiIndexSnow)
        if sparkle, shading.detailTexture == nil {
            shading.detailTexture = Self.projectedNoise
        }
        let lod = has(.lodLandscape) || has(.lodObjects) || has(.noLODLandBlend) ||
            has(.hdLODObjects)
        let snow = !lod && (has(.snow) && !has(.treeAnim) || has(.snowBase))

        let enabled: [(Bool, SurfaceShading.Terms)] = [
            (modelSpace, .modelSpaceNormals),
            (has(.specular), .specular),
            (specularMap != nil, .specularMap),
            (has(.ownEmit), .emissive),
            (glow != nil, .glowMap),
            (lightMask != nil && has(.softLighting), .softLighting),
            (lightMask != nil && has(.rimLighting), .rimLighting),
            (backLight != nil, .backLighting),
            (detail != nil, .faceDetail),
            (height != nil, .parallax),
            (multiLayer != nil, .multiLayer),
            (environment != nil, .environment),
            (shading.environmentMaskTexture != nil, .environmentMask),
            (has(.hairSoftLighting), .hairSoftLighting),
            (has(.anisotropicLighting), .anisotropicLighting),
            (environment != nil && has(.envMapLightFade), .environmentLightFade),
            (has(.externalEmittance), .externalEmittance),
            (sparkle, .sparkle),
            (snow, .snow),
            (!lod && has(.snowBase), .snowBase),
            (noise != nil, .landscapeNoise),
            (isRefraction, .refraction),
            // Fire refraction only scrolls a refraction; alone it changes nothing.
            (isRefraction && has(.fireRefraction), .fireRefraction)
        ]
        shading.terms = enabled.reduce(into: []) { terms, entry in
            if entry.0 {
                terms.insert(entry.1)
            }
        }
        return shading
    }

    /// The block's numbers, before any texture slot or flag decides a term.
    private func parameters() -> SurfaceShading {
        var shading = SurfaceShading()
        shading.emissiveColor = emissiveColor
        shading.emissiveMultiple = emissiveMultiple
        shading.lightingEffect1 = lightingEffect1
        shading.lightingEffect2 = lightingEffect2
        shading.tintColor = tail.tintColor
        shading.environmentScale = shaderType == ShaderType.multiLayer
            ? tail.environmentStrength : tail.environmentMapScale
        shading.multiLayer = SurfaceShading.MultiLayer(
            thickness: tail.innerLayerThickness,
            refractionScale: tail.refractionScale,
            innerScale: tail.innerLayerScale,
            environmentStrength: tail.environmentStrength
        )
        shading.refractionStrength = isRefraction ? refractionStrength : 0
        shading.sparkle = Self.hasSparkleVector(shaderType) ? tail.sparkle : .zero
        return shading
    }

    /// The game's own noise texture for shader type 18, not named by the shape.
    static let landscapeNoise = "textures/terrain/noise.dds"
    /// The game's shared projected noise; its blue channel places the sparkles.
    static let projectedNoise = "textures/effects/projectednoise.dds"

    /// Types 10 and 14 store the four sparkle values after the common fields.
    private static func hasSparkleVector(_ type: UInt32) -> Bool {
        type == ShaderType.snow || type == ShaderType.sparkleSnow
    }

    private func hasEnvironment(multiLayer: Bool) -> Bool {
        switch shaderType {
        case ShaderType.environmentMap: has(.environmentMapping)
        case ShaderType.eye: has(.eyeEnvironmentMapping)
        case ShaderType.multiLayer: multiLayer
        default: false
        }
    }
}
