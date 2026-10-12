// Which shader type, flag, and texture slot turn on each lit-surface term. The
// rules follow NifSkope's open renderer: docs/formats/nif-materials.md.

import Foundation
import OpenSkyFormatsCore

nonisolated extension NIFLightingShaderProperty {
    private enum Flag1 {
        static let specular = 0
        static let environmentMapping = 7
        static let parallax = 11
        static let modelSpaceNormals = 12
        static let eyeEnvironmentMapping = 17
        static let ownEmit = 22
    }

    private enum Flag2 {
        static let glowMap = 6
        static let multiLayerParallax = 24
        static let softLighting = 25
        static let rimLighting = 26
        static let backLighting = 27
    }

    private enum ShaderType {
        static let environmentMap: UInt32 = 1
        static let glow: UInt32 = 2
        static let parallax: UInt32 = 3
        static let faceGen: UInt32 = 4
        static let multiLayer: UInt32 = 11
        static let eye: UInt32 = 16
    }

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
        let modelSpace = hasFlag1(Flag1.modelSpaceNormals)
        let backLight = hasFlag2(Flag2.backLighting) ? slot(7) : nil
        let specularMap = hasFlag1(Flag1.specular) && modelSpace && backLight == nil ? slot(7) : nil
        shading.backLightTexture = backLight ?? specularMap
        let lightMask = hasFlag2(Flag2.softLighting) || hasFlag2(Flag2.rimLighting) ? slot(2) : nil
        let glow = shaderType == ShaderType.glow && hasFlag2(Flag2.glowMap) ? slot(2) : nil
        shading.glowTexture = glow ?? lightMask
        let detail = shaderType == ShaderType.faceGen ? slot(3) : nil
        let height = shaderType == ShaderType.parallax && hasFlag1(Flag1.parallax) ? slot(3) : nil
        shading.detailTexture = detail ?? height
        let multiLayer = shaderType == ShaderType.multiLayer && hasFlag2(Flag2.multiLayerParallax)
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
            (hasFlag1(Flag1.specular), .specular),
            (specularMap != nil, .specularMap),
            (hasFlag1(Flag1.ownEmit), .emissive),
            (glow != nil, .glowMap),
            (lightMask != nil && hasFlag2(Flag2.softLighting), .softLighting),
            (lightMask != nil && hasFlag2(Flag2.rimLighting), .rimLighting),
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
        case ShaderType.environmentMap: hasFlag1(Flag1.environmentMapping)
        case ShaderType.eye: hasFlag1(Flag1.eyeEnvironmentMapping)
        case ShaderType.multiLayer: multiLayer
        default: false
        }
    }
}
