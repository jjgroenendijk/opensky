// Shader flag bits and lighting shader types, with their nif.xml names, and the ones
// a draw term or draw state depends on. `openskycli gaps` lists the rest that the data
// sets. Names: nif.xml `SkyrimShaderPropertyFlags1/2`, `BSLightingShaderType`.

import Foundation

/// One bit of `SkyrimShaderPropertyFlags1` (word 1) or `...Flags2` (word 2).
nonisolated public struct NIFShaderFlag: Hashable, Sendable {
    public let word: Int
    public let bit: Int

    public var name: String {
        let names = word == 1 ? Self.flags1Names : Self.flags2Names
        return "SLSF\(word) \(bit) \(names[bit])"
    }

    /// Every bit set in the two words, word 1 first.
    public static func set(in flags1: UInt32, _ flags2: UInt32) -> [NIFShaderFlag] {
        (0 ..< 32).filter { flags1 & (1 << $0) != 0 }.map { NIFShaderFlag(word: 1, bit: $0) }
            + (0 ..< 32).filter { flags2 & (1 << $0) != 0 }.map { NIFShaderFlag(word: 2, bit: $0) }
    }

    static let flags1Names = [
        "Specular", "Skinned", "Temp_Refraction", "Vertex_Alpha", "Greyscale_To_PaletteColor",
        "Greyscale_To_PaletteAlpha", "Use_Falloff", "Environment_Mapping", "Recieve_Shadows",
        "Cast_Shadows", "Facegen_Detail_Map", "Parallax", "Model_Space_Normals",
        "Non_Projective_Shadows", "Landscape", "Refraction", "Fire_Refraction",
        "Eye_Environment_Mapping", "Hair_Soft_Lighting", "Screendoor_Alpha_Fade",
        "Localmap_Hide_Secret", "FaceGen_RGB_Tint", "Own_Emit", "Projected_UV",
        "Multiple_Textures", "Remappable_Textures", "Decal", "Dynamic_Decal",
        "Parallax_Occlusion", "External_Emittance", "Soft_Effect", "ZBuffer_Test"
    ]

    static let flags2Names = [
        "ZBuffer_Write", "LOD_Landscape", "LOD_Objects", "No_Fade", "Double_Sided",
        "Vertex_Colors", "Glow_Map", "Assume_Shadowmask", "Packed_Tangent", "Multi_Index_Snow",
        "Vertex_Lighting", "Uniform_Scale", "Fit_Slope", "Billboard", "No_LOD_Land_Blend",
        "EnvMap_Light_Fade", "Wireframe", "Weapon_Blood", "Hide_On_Local_Map", "Premult_Alpha",
        "Cloud_LOD", "Anisotropic_Lighting", "No_Transparency_Multisampling", "Unused01",
        "Multi_Layer_Parallax", "Soft_Lighting", "Rim_Lighting", "Back_Lighting", "Unused02",
        "Tree_Anim", "Effect_Lighting", "HD_LOD_Objects"
    ]
}

nonisolated extension NIFShaderFlag {
    static let specular = NIFShaderFlag(word: 1, bit: 0)
    static let vertexAlpha = NIFShaderFlag(word: 1, bit: 3)
    static let greyscaleToPaletteColor = NIFShaderFlag(word: 1, bit: 4)
    static let greyscaleToPaletteAlpha = NIFShaderFlag(word: 1, bit: 5)
    static let useFalloff = NIFShaderFlag(word: 1, bit: 6)
    static let environmentMapping = NIFShaderFlag(word: 1, bit: 7)
    static let parallax = NIFShaderFlag(word: 1, bit: 11)
    static let modelSpaceNormals = NIFShaderFlag(word: 1, bit: 12)
    static let refraction = NIFShaderFlag(word: 1, bit: 15)
    static let eyeEnvironmentMapping = NIFShaderFlag(word: 1, bit: 17)
    static let ownEmit = NIFShaderFlag(word: 1, bit: 22)
    static let softEffect = NIFShaderFlag(word: 1, bit: 30)
    static let zBufferTest = NIFShaderFlag(word: 1, bit: 31)
    static let zBufferWrite = NIFShaderFlag(word: 2, bit: 0)
    static let doubleSided = NIFShaderFlag(word: 2, bit: 4)
    static let vertexColors = NIFShaderFlag(word: 2, bit: 5)
    static let glowMap = NIFShaderFlag(word: 2, bit: 6)
    static let multiLayerParallax = NIFShaderFlag(word: 2, bit: 24)
    static let softLighting = NIFShaderFlag(word: 2, bit: 25)
    static let rimLighting = NIFShaderFlag(word: 2, bit: 26)
    static let backLighting = NIFShaderFlag(word: 2, bit: 27)
    static let treeAnim = NIFShaderFlag(word: 2, bit: 29)

    /// `BSLightingShaderProperty` bits a surface term or draw state depends on.
    public static let lightingRead: Set<NIFShaderFlag> = [
        specular, environmentMapping, parallax, modelSpaceNormals, refraction,
        eyeEnvironmentMapping, ownEmit, doubleSided, glowMap, multiLayerParallax,
        softLighting, rimLighting, backLighting, treeAnim
    ]

    /// `BSEffectShaderProperty` bits `EffectShading` or the draw state depends on.
    /// Soft effect and the depth bits are decoded, and no draw uses them yet.
    public static let effectRead: Set<NIFShaderFlag> = [
        vertexAlpha, greyscaleToPaletteColor, greyscaleToPaletteAlpha, useFalloff,
        doubleSided, vertexColors
    ]
}

/// `BSLightingShaderType` values, with the ones a surface term depends on.
nonisolated public enum NIFLightingShaderType: Sendable {
    static let environmentMap: UInt32 = 1
    static let glow: UInt32 = 2
    static let parallax: UInt32 = 3
    static let faceGen: UInt32 = 4
    static let skinTint: UInt32 = 5
    static let hairTint: UInt32 = 6
    static let multiLayer: UInt32 = 11
    static let eye: UInt32 = 16

    /// Type 0 is the plain default, which needs no rule of its own.
    public static let engineRead: Set<UInt32> = [
        0, environmentMap, glow, parallax, faceGen, skinTint, hairTint, multiLayer, eye
    ]

    public static func name(_ type: UInt32) -> String {
        let index = Int(type)
        return index < names.count ? "\(type) \(names[index])" : "\(type) unknown"
    }

    private static let names = [
        "Default", "Environment Map", "Glow Shader", "Parallax", "Face Tint", "Skin Tint",
        "Hair Tint", "Parallax Occ", "Multitexture Landscape", "LOD Landscape", "Snow",
        "MultiLayer Parallax", "Tree Anim", "LOD Objects", "Sparkle Snow", "LOD Objects HD",
        "Eye Envmap", "Cloud", "LOD Landscape Noise", "Multitexture Landscape LOD Blend",
        "FO4 Dismemberment"
    ]
}
