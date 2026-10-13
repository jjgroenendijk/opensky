// Which shader type, flag, and texture slot turn on each lit-surface term. The
// rules follow NifSkope's open renderer: docs/formats/nif-materials.md.

import Foundation
import OpenSkyFormatsCore

nonisolated extension NIFLightingShaderProperty {
    private typealias ShaderType = NIFLightingShaderType

    /// A term whose texture slot is empty stays off.
    public func surfaceShading(textures: NIFShaderTextureSet?) -> SurfaceShading {
        var shading = SurfaceShading()
        let slot = { (index: Int) in textures?.path(slot: index) }
        shading.emissiveColor = emissiveColor
        shading.emissiveMultiple = emissiveMultiple
        shading.lightingEffect1 = lightingEffect1
        shading.lightingEffect2 = lightingEffect2
        shading.tintColor = tail.tintColor
        shading.environmentScale = tail.environmentMapScale
        shading.multiLayer = SurfaceShading.MultiLayer(
            thickness: tail.innerLayerThickness,
            refractionScale: tail.refractionScale,
            innerScale: tail.innerLayerScale,
            environmentStrength: tail.environmentStrength
        )
        let modelSpace = has(.modelSpaceNormals)
        let backLight = has(.backLighting) ? slot(7) : nil
        let specularMap = has(.specular) && modelSpace && backLight == nil ? slot(7) : nil
        shading.backLightTexture = backLight ?? specularMap
        let lightMask = has(.softLighting) || has(.rimLighting) ? slot(2) : nil
        let glow = shaderType == ShaderType.glow && has(.glowMap) ? slot(2) : nil
        shading.glowTexture = glow ?? lightMask
        let detail = shaderType == ShaderType.faceGen ? slot(3) : nil
        let height = shaderType == ShaderType.parallax && has(.parallax) ? slot(3) : nil
        shading.detailTexture = detail ?? height
        let multiLayer = shaderType == ShaderType.multiLayer && has(.multiLayerParallax)
            ? slot(6) : nil
        shading.innerLayerTexture = multiLayer
        let environment = hasEnvironment(multiLayer: multiLayer != nil) ? slot(4) : nil
        shading.environmentTexture = environment
        shading.environmentMaskTexture = environment != nil ? slot(5) : nil
        if shaderType == ShaderType.multiLayer {
            shading.environmentScale = tail.environmentStrength
        }

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
            (shading.environmentMaskTexture != nil, .environmentMask)
        ]
        shading.terms = enabled.reduce(into: []) { terms, entry in
            if entry.0 {
                terms.insert(entry.1)
            }
        }
        return shading
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
