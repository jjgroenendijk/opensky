// BSLightingShaderProperty: the material of a Skyrim SE static — shader
// type/flags, UV transform, texture set ref, alpha, glossiness, specular.
// Skyrim layout only (BS stream 83/100): the shader type uint32 precedes the
// NiObjectNET name for this one block type (nif.xml NiObjectNET "Shader
// Type", onlyT=BSLightingShaderProperty); FO4+ moves fields around and is
// rejected. Fields after specular strength (lighting effects + the
// shader-type-conditional tail) are not needed by the M2 shader and stay
// unread inside the size-sliced block payload.
//
// Reference: NifTools nif.xml (BSLightingShaderProperty,
// SkyrimShaderPropertyFlags1/2, NiObjectNET).
//   https://github.com/niftools/nifxml/blob/develop/nif.xml
// Layout documented in docs/formats/nif-materials.md.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public struct NIFLightingShaderProperty: Sendable {
    /// nif.xml BSLightingShaderType: 0 default, 1 environment map, 5 skin
    /// tint, … — selects the conditional tail this decoder never reads.
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
    /// Material opacity, 1 = opaque (vanilla range reaches past 1 to shape
    /// alpha falloff).
    public let alpha: Float
    /// Specular power.
    public let glossiness: Float
    public let specularColor: SIMD3<Float>
    public let specularStrength: Float

    /// SLSF2 bit 4 Double_Sided -> cull mode none.
    public var isDoubleSided: Bool {
        shaderFlags2 & 0x10 != 0
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
        reader.skip(16) // emissive color (3f) + emissive multiple (f)
        reader.skip(4) // texture clamp mode
        alpha = try reader.readFloat32()
        reader.skip(4) // refraction strength
        glossiness = try reader.readFloat32()
        specularColor = try reader.readVector3()
        specularStrength = try reader.readFloat32()
        // lighting effect 1/2 + shader-type-conditional tail: unread.
    }
}
