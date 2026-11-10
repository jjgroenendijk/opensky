// BSLightingShaderProperty: the material of a lit shape. Skyrim streams only; for
// this block a uint32 shader type comes before the name. The per-type tail is read
// when present. Layout: docs/formats/nif-materials.md.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated struct NIFLightingShaderProperty: Sendable {
    /// nif.xml `BSLightingShaderType`; `NIFLightingShaderType` names the values.
    let shaderType: UInt32
    let name: String?
    /// Raw SkyrimShaderPropertyFlags1/2; derived accessors below for the
    /// bits the renderer consumes.
    let shaderFlags1: UInt32
    let shaderFlags2: UInt32
    let uvOffset: SIMD2<Float>
    let uvScale: SIMD2<Float>
    /// BSShaderTextureSet block ref; -1 = none.
    let textureSetRef: Int32
    let emissiveColor: SIMD3<Float>
    let emissiveMultiple: Float
    /// Material opacity, 1 = opaque (vanilla range reaches past 1 to shape
    /// alpha falloff).
    let alpha: Float
    /// How far a refraction shape bends the scene behind it, 0 to 1.
    let refractionStrength: Float
    /// Specular power.
    let glossiness: Float
    let specularColor: SIMD3<Float>
    let specularStrength: Float
    /// Soft-lighting wrap amount.
    let lightingEffect1: Float
    /// Rim-light power.
    let lightingEffect2: Float
    /// The fields only one shader type has. Defaults when the block ends early.
    let tail: Tail

    nonisolated struct Tail: Equatable, Sendable {
        /// Type 1. Type 16 stores its eye cubemap scale here too.
        var environmentMapScale: Float = 1
        /// Type 5 skin tint or type 6 hair tint; the game replaces it per actor.
        var tintColor: SIMD3<Float>?
        /// Type 11.
        var innerLayerThickness: Float = 5
        var refractionScale: Float = 0.25
        var innerLayerScale = SIMD2<Float>(1, 1)
        var environmentStrength: Float = 1
        /// Type 14. The field meanings are not documented.
        var sparkle = SIMD4<Float>.zero

        init() {}
    }

    /// SLSF2 bit 4 Double_Sided -> cull mode none.
    var isDoubleSided: Bool {
        has(.doubleSided)
    }

    /// SLSF2 bit 29 Tree_Anim: the vertex alpha is the branch's wind weight, not opacity.
    var isTreeAnimated: Bool {
        has(.treeAnim)
    }

    /// SLSF1 bit 15 Refraction: the shape bends what is behind it, such as the
    /// heat haze over a fire, and its slot 0 texture is a normal map.
    var isRefraction: Bool {
        has(.refraction)
    }

    /// Shader type 4: a FaceGen head, tinted by texture slot 6.
    var isFaceGen: Bool {
        shaderType == NIFLightingShaderType.faceGen
    }

    /// Shader type 5 with SLSF1 bit 21: skin the actor's skin colour tints.
    var isSkinTint: Bool {
        shaderType == NIFLightingShaderType.skinTint && has(.faceGenRGBTint)
    }

    /// SLSF1 bit 3: without it the vertex alpha is ignored. SLSF2 bit 5: the same for
    /// the vertex colour. Tree animation stores wind weight in the alpha.
    var usesVertexAlpha: Bool {
        has(.vertexAlpha) && !isTreeAnimated
    }

    var usesVertexColors: Bool {
        has(.vertexColors)
    }

    var drawState: MaterialDrawState {
        var state = MaterialDrawState()
        state.depthTest = has(.zBufferTest)
        state.depthWrite = has(.zBufferWrite)
        state.decal = has(.decal) || has(.dynamicDecal)
        state.distantLOD = has(.lodLandscape) || has(.lodObjects) || has(.hdLODObjects)
        state.castsShadows = has(.castShadows) && !state.distantLOD && !isRefraction
        // Assume_Shadowmask: the game shades it from its screen shadow mask instead.
        state.receivesShadows = (has(.receiveShadows) || has(.assumeShadowmask))
            && !state.distantLOD
        state.screenDoor = has(.screendoorAlphaFade)
        state.windWeighted = isTreeAnimated
        return state
    }

    func has(_ flag: NIFShaderFlag) -> Bool {
        (flag.word == 1 ? shaderFlags1 : shaderFlags2) & (1 << flag.bit) != 0
    }

    init(data: Data, header: NIFHeader) throws {
        let streamVersion = header.bsStream?.version ?? 0
        guard streamVersion == 83 || streamVersion == 100 else {
            throw NIFError.unsupported(
                "BSLightingShaderProperty needs a Skyrim BS stream (83/100), "
                    + "got \(streamVersion)"
            )
        }
        var reader = BinaryReader(data)
        shaderType = try reader.readUInt32()
        name = try NIFObjectNET(reader: &reader, header: header).name
        shaderFlags1 = try reader.readUInt32()
        shaderFlags2 = try reader.readUInt32()
        uvOffset = try SIMD2(reader.readFloat32(), reader.readFloat32())
        uvScale = try SIMD2(reader.readFloat32(), reader.readFloat32())
        textureSetRef = try Int32(bitPattern: reader.readUInt32())
        emissiveColor = try reader.readVector3()
        emissiveMultiple = try reader.readFloat32()
        reader.skip(4) // texture clamp mode
        alpha = try reader.readFloat32()
        refractionStrength = try reader.readFloat32()
        glossiness = try reader.readFloat32()
        specularColor = try reader.readVector3()
        specularStrength = try reader.readFloat32()
        lightingEffect1 = attempt { try reader.readFloat32() } ?? 0.3
        lightingEffect2 = attempt { try reader.readFloat32() } ?? 2
        tail = Self.readTail(shaderType: shaderType, reader: &reader)
    }

    /// A short block keeps the defaults: some files end before the tail.
    private static func readTail(shaderType: UInt32, reader: inout BinaryReader) -> Tail {
        var tail = Tail()
        switch shaderType {
        case 1, 16:
            tail.environmentMapScale = attempt { try reader.readFloat32() } ?? 1
        case 5, 6:
            tail.tintColor = attempt { try reader.readVector3() }
        case 14:
            if
                let sparkle = attempt({
                    try SIMD4(
                        reader.readFloat32(), reader.readFloat32(), reader.readFloat32(),
                        reader.readFloat32()
                    )
                })
            {
                tail.sparkle = sparkle
            }
        case 11:
            tail.innerLayerThickness = attempt { try reader.readFloat32() } ?? 5
            tail.refractionScale = attempt { try reader.readFloat32() } ?? 0.25
            if let scale = attempt({ try SIMD2(reader.readFloat32(), reader.readFloat32()) }) {
                tail.innerLayerScale = scale
            }
            tail.environmentStrength = attempt { try reader.readFloat32() } ?? 1
        default:
            break
        }
        return tail
    }
}
