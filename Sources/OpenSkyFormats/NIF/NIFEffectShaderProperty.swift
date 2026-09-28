// BSEffectShaderProperty: the material of a Skyrim SE effect shape — glow,
// additive/particle, and other non-lit effects. Holds shader flags, a UV
// transform, an inline source texture path, angular falloff, a base
// (emissive) color + multiplier, and a greyscale palette texture.
//
// Skyrim layout only (BS stream 83/100). Unlike BSLightingShaderProperty
// there is no shader-type uint32 before the NiObjectNET name (nif.xml
// NiObjectNET "Shader Type" is onlyT=BSLightingShaderProperty), so the block
// starts directly with the name. Fields gated on FO4+/F76/Starfield in
// nif.xml (SF1/SF2 CRC arrays, refraction power, env/normal/mask textures,
// luminance) do not appear at BS stream 83/100 and are absent here; FO4+ is
// rejected via the stream guard. The three bytes after texture clamp mode
// (lighting influence, env-map min LOD, unused) are read past but not kept —
// no consumer yet.
//
// Reference: NifTools nif.xml (BSEffectShaderProperty, BSShaderProperty,
// NiObjectNET, SkyrimShaderPropertyFlags1/2, SizedString, TexCoord, Color4).
//   https://github.com/niftools/nifxml/blob/develop/nif.xml
// Layout documented in docs/formats/nif-materials.md.

import Foundation
import simd

nonisolated package struct NIFEffectShaderProperty: Equatable {
    package let name: String?
    /// Raw SkyrimShaderPropertyFlags1/2; derived accessors below expose the
    /// bits the renderer consumes.
    package let shaderFlags1: UInt32
    package let shaderFlags2: UInt32
    package let uvOffset: SIMD2<Float>
    package let uvScale: SIMD2<Float>
    /// Inline effect texture path (nif.xml SizedString), raw as stored. Empty
    /// -> nil. `sourceTexturePath` gives the VFS-normalized key.
    package let sourceTexture: String?
    /// nif.xml TexClampMode byte (0 clamp S/T … 3 wrap S/T).
    package let textureClampMode: UInt8
    /// Cosine-of-angle falloff endpoints + their opacity multipliers; active
    /// when `usesFalloff` is set (SLSF1 Use_Falloff).
    package let falloffStartAngle: Float
    package let falloffStopAngle: Float
    package let falloffStartOpacity: Float
    package let falloffStopOpacity: Float
    /// nif.xml "Base Color" (Color4) — the effect's emissive color incl.
    /// alpha; scaled by `baseColorScale` ("Base Color Scale", RGB multiplier).
    package let baseColor: SIMD4<Float>
    package let baseColorScale: Float
    /// Depth over which the soft-particle edge fades (nif.xml Soft Falloff
    /// Depth); used when `isSoftEffect` is set.
    package let softFalloffDepth: Float
    /// Greyscale palette texture (nif.xml SizedString), raw as stored. Feeds
    /// the greyscale-to-palette color/alpha paths. Empty -> nil.
    package let greyscaleTexture: String?

    /// VFS lookup key for the effect texture (see NIFShaderTextureSet.vfsKey).
    package var sourceTexturePath: String? {
        sourceTexture.flatMap(NIFShaderTextureSet.vfsKey(for:))
    }

    /// VFS lookup key for the greyscale palette texture.
    package var greyscaleTexturePath: String? {
        greyscaleTexture.flatMap(NIFShaderTextureSet.vfsKey(for:))
    }

    /// SLSF2 bit 4 Double_Sided -> cull mode none.
    package var isDoubleSided: Bool {
        shaderFlags2 & 0x10 != 0
    }

    /// SLSF1 bit 30 Soft_Effect -> soft-particle depth fade.
    package var isSoftEffect: Bool {
        shaderFlags1 & 0x4000_0000 != 0
    }

    /// SLSF1 bit 4 Greyscale_To_PaletteColor -> RGB from palette texture.
    package var usesGreyscaleToPaletteColor: Bool {
        shaderFlags1 & 0x10 != 0
    }

    /// SLSF1 bit 5 Greyscale_To_PaletteAlpha -> alpha from palette texture.
    package var usesGreyscaleToPaletteAlpha: Bool {
        shaderFlags1 & 0x20 != 0
    }

    /// SLSF1 bit 6 Use_Falloff -> apply the angular falloff fields.
    package var usesFalloff: Bool {
        shaderFlags1 & 0x40 != 0
    }

    /// SLSF1 bit 3 Vertex_Alpha -> vertex-color alpha modulates opacity.
    package var hasVertexAlpha: Bool {
        shaderFlags1 & 0x08 != 0
    }

    /// SLSF1 bit 31 ZBuffer_Test (nif.xml places ZBuffer_Test in flags 1, not
    /// flags 2) -> depth test enabled.
    package var isZBufferTest: Bool {
        shaderFlags1 & 0x8000_0000 != 0
    }

    /// SLSF2 bit 0 ZBuffer_Write cleared -> no depth writes (typical for
    /// additive/transparent effects).
    package var isZBufferWriteDisabled: Bool {
        shaderFlags2 & 0x01 == 0
    }

    package init(data: Data, header: NIFHeader) throws {
        let streamVersion = header.bsStream?.version ?? 0
        guard streamVersion == 83 || streamVersion == 100 else {
            throw NIFError.unsupported(
                "BSEffectShaderProperty needs a Skyrim BS stream (83/100), "
                    + "got \(streamVersion)"
            )
        }
        var reader = BinaryReader(data)
        name = try NIFObjectNET(reader: &reader, header: header).name
        shaderFlags1 = try reader.readUInt32()
        shaderFlags2 = try reader.readUInt32()
        uvOffset = try SIMD2(reader.readFloat32(), reader.readFloat32())
        uvScale = try SIMD2(reader.readFloat32(), reader.readFloat32())
        sourceTexture = try Self.readSizedString(&reader)
        textureClampMode = try reader.readUInt8()
        reader.skip(3) // lighting influence + env-map min LOD + unused byte
        falloffStartAngle = try reader.readFloat32()
        falloffStopAngle = try reader.readFloat32()
        falloffStartOpacity = try reader.readFloat32()
        falloffStopOpacity = try reader.readFloat32()
        baseColor = try SIMD4(
            reader.readFloat32(),
            reader.readFloat32(),
            reader.readFloat32(),
            reader.readFloat32()
        )
        baseColorScale = try reader.readFloat32()
        softFalloffDepth = try reader.readFloat32()
        greyscaleTexture = try Self.readSizedString(&reader)
        // No further fields at BS stream 83/100 (env/normal/mask + F76/STF
        // tails are FO4-and-later only, rejected by the stream guard).
    }

    /// Read a nif.xml SizedString (uint32 length + that many bytes). Empty ->
    /// nil. Length is bounds-checked so junk lengths throw rather than crash.
    private static func readSizedString(_ reader: inout BinaryReader) throws -> String? {
        let length = try Int(reader.readUInt32())
        guard length <= reader.bytesRemaining else {
            throw NIFError.malformed("effect texture length \(length) exceeds block")
        }
        guard length > 0 else { return nil }
        let bytes = try reader.read(count: length)
        return GameText.decode(bytes)
    }
}
