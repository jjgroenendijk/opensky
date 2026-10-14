// BSLightingShaderProperty: the material of a lit shape. Skyrim streams only; for
// this block a uint32 shader type comes before the name. The per-type tail is read
// when present. Layout: docs/formats/nif-materials.md.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public struct NIFLightingShaderProperty: Sendable {
    /// nif.xml `BSLightingShaderType`; `NIFLightingShaderType` names the values.
    public let shaderType: UInt32
    public let name: String?
    /// Raw SkyrimShaderPropertyFlags1/2; derived accessors below for the
    /// bits the renderer consumes.
    public let shaderFlags1: UInt32
    public let shaderFlags2: UInt32
    public let uvOffset: SIMD2<Float>
    public let uvScale: SIMD2<Float>
    /// BSShaderTextureSet block ref; -1 = none.
    public let textureSetRef: Int32
    public let emissiveColor: SIMD3<Float>
    public let emissiveMultiple: Float
    /// Material opacity, 1 = opaque (vanilla range reaches past 1 to shape
    /// alpha falloff).
    public let alpha: Float
    /// How far a refraction shape bends the scene behind it, 0 to 1.
    public let refractionStrength: Float
    /// Specular power.
    public let glossiness: Float
    public let specularColor: SIMD3<Float>
    public let specularStrength: Float
    /// Soft-lighting wrap amount.
    public let lightingEffect1: Float
    /// Rim-light power.
    public let lightingEffect2: Float
    /// The fields only one shader type has. Defaults when the block ends early.
    public let tail: Tail

    nonisolated public struct Tail: Equatable, Sendable {
        /// Type 1. Type 16 stores its eye cubemap scale here too.
        public var environmentMapScale: Float = 1
        /// Type 5 skin tint or type 6 hair tint; the game replaces it per actor.
        public var tintColor: SIMD3<Float>?
        /// Type 11.
        public var innerLayerThickness: Float = 5
        public var refractionScale: Float = 0.25
        public var innerLayerScale = SIMD2<Float>(1, 1)
        public var environmentStrength: Float = 1
        /// Type 14. The field meanings are not documented.
        public var sparkle = SIMD4<Float>.zero

        public init() {}
    }

    /// SLSF2 bit 4 Double_Sided -> cull mode none.
    public var isDoubleSided: Bool {
        has(.doubleSided)
    }

    /// SLSF2 bit 29 Tree_Anim: the vertex alpha is the branch's wind weight, not opacity.
    public var isTreeAnimated: Bool {
        has(.treeAnim)
    }

    /// SLSF1 bit 15 Refraction: the shape bends what is behind it, such as the
    /// heat haze over a fire, and its slot 0 texture is a normal map.
    public var isRefraction: Bool {
        has(.refraction)
    }

    /// Shader type 4: a FaceGen head, tinted by texture slot 6.
    public var isFaceGen: Bool {
        shaderType == NIFLightingShaderType.faceGen
    }

    /// Shader type 5 with SLSF1 bit 21: skin the actor's skin colour tints.
    public var isSkinTint: Bool {
        shaderType == NIFLightingShaderType.skinTint && has(.faceGenRGBTint)
    }

    /// SLSF1 bit 3: without it the vertex alpha is ignored. SLSF2 bit 5: the same for
    /// the vertex colour. Tree animation stores wind weight in the alpha.
    public var usesVertexAlpha: Bool {
        has(.vertexAlpha) && !isTreeAnimated
    }

    public var usesVertexColors: Bool {
        has(.vertexColors)
    }

    public var drawState: MaterialDrawState {
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
        return state
    }

    func has(_ flag: NIFShaderFlag) -> Bool {
        (flag.word == 1 ? shaderFlags1 : shaderFlags2) & (1 << flag.bit) != 0
    }

    public init(data: Data, header: NIFHeader) throws {
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
        lightingEffect1 = (try? reader.readFloat32()) ?? 0.3
        lightingEffect2 = (try? reader.readFloat32()) ?? 2
        tail = Self.readTail(shaderType: shaderType, reader: &reader)
    }

    /// A short block keeps the defaults: some files end before the tail.
    private static func readTail(shaderType: UInt32, reader: inout BinaryReader) -> Tail {
        var tail = Tail()
        switch shaderType {
        case 1, 16:
            tail.environmentMapScale = (try? reader.readFloat32()) ?? 1
        case 5, 6:
            tail.tintColor = try? reader.readVector3()
        case 14:
            if
                let sparkle = try? SIMD4(
                    reader.readFloat32(), reader.readFloat32(), reader.readFloat32(),
                    reader.readFloat32()
                )
            {
                tail.sparkle = sparkle
            }
        case 11:
            tail.innerLayerThickness = (try? reader.readFloat32()) ?? 5
            tail.refractionScale = (try? reader.readFloat32()) ?? 0.25
            if let scale = try? SIMD2(reader.readFloat32(), reader.readFloat32()) {
                tail.innerLayerScale = scale
            }
            tail.environmentStrength = (try? reader.readFloat32()) ?? 1
        default:
            break
        }
        return tail
    }
}
