// Synthetic NIF byte builder shared by NIF parser tests. Fixtures are built
// in code — never extracted game files (AGENTS.md "Legal & IP boundary").
// Layouts follow NifTools nif.xml (Header, BSStreamHeader, Footer,
// NiObjectNET, NiAVObject, NiNode, BSTriShape, BSVertexDataSSE); see
// docs/formats/nif.md.

import Foundation
import simd

enum NIFFixture {
    static let versionLine = "Gamebryo File Format, Version 20.2.0.7"
    static let version: UInt32 = 0x1402_0007

    /// One block as fed to `header(blocks:)`: type name + raw payload bytes.
    struct Block {
        let type: String
        let data: Data
        /// Set to test the PhysX flag bit on the block type index.
        var physXFlag = false

        init(_ type: String, _ data: Data, physXFlag: Bool = false) {
            self.type = type
            self.data = data
            self.physXFlag = physXFlag
        }
    }

    /// uint32 length + bytes, no terminator (nif.xml SizedString).
    static func sizedString(_ string: String) -> Data {
        sizedString(raw: Data(string.utf8))
    }

    /// SizedString from raw bytes — for garbage-byte decode tests.
    static func sizedString(raw bytes: Data) -> Data {
        var out = Data()
        out.appendUInt32(UInt32(bytes.count))
        out.append(bytes)
        return out
    }

    /// byte length including a trailing null (nif.xml ExportString).
    static func exportString(_ string: String) -> Data {
        var out = Data([UInt8(string.utf8.count + 1)])
        out.append(Data(string.utf8))
        out.append(0)
        return out
    }

    /// Header bytes. Block type table is derived from `blocks` in first-seen
    /// order. `userVersion` >= 3 emits a BSStreamHeader.
    static func header(
        versionLine: String = versionLine,
        version: UInt32 = version,
        endian: UInt8 = 1,
        userVersion: UInt32 = 12,
        bsVersion: UInt32 = 100,
        blocks: [Block] = [],
        strings: [String] = [],
        groups: [UInt32] = []
    ) -> Data {
        var types: [String] = []
        for block in blocks where !types.contains(block.type) {
            types.append(block.type)
        }

        var out = Data(versionLine.utf8)
        out.append(0x0A)
        out.appendUInt32(version)
        out.append(endian)
        out.appendUInt32(userVersion)
        out.appendUInt32(UInt32(blocks.count))
        if userVersion >= 3 {
            out.appendUInt32(bsVersion)
            out.append(exportString("OpenSky Tests"))
            out.append(exportString(""))
            out.append(exportString(""))
        }
        out.appendUInt16(UInt16(types.count))
        for type in types {
            out.append(sizedString(type))
        }
        for block in blocks {
            let index = UInt16(types.firstIndex(of: block.type) ?? 0)
            out.appendUInt16(block.physXFlag ? index | 0x8000 : index)
        }
        for block in blocks {
            out.appendUInt32(UInt32(block.data.count))
        }
        out.appendUInt32(UInt32(strings.count))
        out.appendUInt32(UInt32(strings.map(\.utf8.count).max() ?? 0))
        for string in strings {
            out.append(sizedString(string))
        }
        out.appendUInt32(UInt32(groups.count))
        for group in groups {
            out.appendUInt32(group)
        }
        return out
    }

    /// NiObjectNET + NiAVObject prefix bytes shared by node + shape payload
    /// builders (Skyrim stream: uint32 flags, no property list). Rotation is
    /// nine floats in file order m11 m21 m31 | m12 m22 m32 | m13 m23 m33
    /// (nif.xml Matrix33, column-major).
    static func avObjectPrefix(
        nameIndex: UInt32 = 0xFFFF_FFFF,
        extraDataRefs: [Int32] = [],
        controllerRef: Int32 = -1,
        flags: UInt32 = 0xE,
        translation: SIMD3<Float> = .zero,
        rotationColumns: [Float] = [1, 0, 0, 0, 1, 0, 0, 0, 1],
        scale: Float = 1,
        collisionRef: Int32 = -1
    ) -> Data {
        var out = Data()
        out.appendUInt32(nameIndex)
        out.appendUInt32(UInt32(extraDataRefs.count))
        for ref in extraDataRefs {
            out.appendUInt32(UInt32(bitPattern: ref))
        }
        out.appendUInt32(UInt32(bitPattern: controllerRef))
        out.appendUInt32(flags)
        out.appendFloat32(translation.x)
        out.appendFloat32(translation.y)
        out.appendFloat32(translation.z)
        for element in rotationColumns {
            out.appendFloat32(element)
        }
        out.appendFloat32(scale)
        out.appendUInt32(UInt32(bitPattern: collisionRef))
        return out
    }

    /// NiNode payload: AV-object prefix, children refs, effects refs.
    static func niNode(
        prefix: Data = avObjectPrefix(),
        children: [Int32] = [],
        effects: [Int32] = []
    ) -> Data {
        var out = prefix
        out.appendUInt32(UInt32(children.count))
        for child in children {
            out.appendUInt32(UInt32(bitPattern: child))
        }
        out.appendUInt32(UInt32(effects.count))
        for effect in effects {
            out.appendUInt32(UInt32(bitPattern: effect))
        }
        return out
    }

    /// BSTriShape payload (SSE stream layout). `vertexRecords` are raw
    /// per-vertex bytes so tests state the interleaved layout explicitly;
    /// the BSVertexDesc is assembled from `attributes` + `strideDwords`.
    static func bsTriShape(
        prefix: Data = avObjectPrefix(),
        center: SIMD3<Float> = .zero,
        radius: Float = 0,
        skinRef: Int32 = -1,
        shaderPropertyRef: Int32 = -1,
        alphaPropertyRef: Int32 = -1,
        attributes: UInt16,
        strideDwords: Int,
        vertexRecords: [Data] = [],
        triangles: [UInt16] = [],
        dataSizeOverride: Int? = nil,
        particleData: Data = Data()
    ) -> Data {
        var out = prefix
        out.appendFloat32(center.x)
        out.appendFloat32(center.y)
        out.appendFloat32(center.z)
        out.appendFloat32(radius)
        out.appendUInt32(UInt32(bitPattern: skinRef))
        out.appendUInt32(UInt32(bitPattern: shaderPropertyRef))
        out.appendUInt32(UInt32(bitPattern: alphaPropertyRef))
        out.appendUInt64(UInt64(strideDwords & 0xF) | UInt64(attributes) << 44)
        out.appendUInt16(UInt16(triangles.count / 3))
        out.appendUInt16(UInt16(vertexRecords.count))
        let dataSize = dataSizeOverride
            ?? vertexRecords.reduce(0) { $0 + $1.count } + triangles.count * 2
        out.appendUInt32(UInt32(dataSize))
        for record in vertexRecords {
            out.append(record)
        }
        for index in triangles {
            out.appendUInt16(index)
        }
        out.appendUInt32(UInt32(particleData.count))
        out.append(particleData)
        return out
    }

    /// NiObjectNET-only prefix (property blocks): name, extra refs, controller.
    static func objectNETPrefix(
        nameIndex: UInt32 = 0xFFFF_FFFF,
        extraDataRefs: [Int32] = [],
        controllerRef: Int32 = -1
    ) -> Data {
        var out = Data()
        out.appendUInt32(nameIndex)
        out.appendUInt32(UInt32(extraDataRefs.count))
        for ref in extraDataRefs {
            out.appendUInt32(UInt32(bitPattern: ref))
        }
        out.appendUInt32(UInt32(bitPattern: controllerRef))
        return out
    }

    /// BSLightingShaderProperty payload, Skyrim stream layout. `tail` stands
    /// in for lighting effects + the shader-type-conditional fields the
    /// decoder never reads.
    static func bsLightingShaderProperty(
        shaderType: UInt32 = 0,
        nameIndex: UInt32 = 0xFFFF_FFFF,
        shaderFlags1: UInt32 = 0x8240_0301,
        shaderFlags2: UInt32 = 0x8021,
        uvOffset: SIMD2<Float> = .zero,
        uvScale: SIMD2<Float> = SIMD2(1, 1),
        textureSetRef: Int32 = -1,
        emissiveColor: SIMD3<Float> = .zero,
        emissiveMultiple: Float = 1,
        clampMode: UInt32 = 3,
        alpha: Float = 1,
        refractionStrength: Float = 0,
        glossiness: Float = 80,
        specularColor: SIMD3<Float> = SIMD3(1, 1, 1),
        specularStrength: Float = 1,
        tail: Data = Data(count: 8)
    ) -> Data {
        var out = Data()
        out.appendUInt32(shaderType)
        out.append(objectNETPrefix(nameIndex: nameIndex))
        out.appendUInt32(shaderFlags1)
        out.appendUInt32(shaderFlags2)
        out.appendFloat32(uvOffset.x)
        out.appendFloat32(uvOffset.y)
        out.appendFloat32(uvScale.x)
        out.appendFloat32(uvScale.y)
        out.appendUInt32(UInt32(bitPattern: textureSetRef))
        out.appendFloat32(emissiveColor.x)
        out.appendFloat32(emissiveColor.y)
        out.appendFloat32(emissiveColor.z)
        out.appendFloat32(emissiveMultiple)
        out.appendUInt32(clampMode)
        out.appendFloat32(alpha)
        out.appendFloat32(refractionStrength)
        out.appendFloat32(glossiness)
        out.appendFloat32(specularColor.x)
        out.appendFloat32(specularColor.y)
        out.appendFloat32(specularColor.z)
        out.appendFloat32(specularStrength)
        out.append(tail)
        return out
    }

    /// BSShaderTextureSet payload: uint32 count + SizedString paths.
    static func bsShaderTextureSet(paths: [String]) -> Data {
        var out = Data()
        out.appendUInt32(UInt32(paths.count))
        for path in paths {
            out.append(sizedString(path))
        }
        return out
    }

    /// NiAlphaProperty payload: NiObjectNET prefix + flags + threshold.
    static func niAlphaProperty(
        nameIndex: UInt32 = 0xFFFF_FFFF,
        flags: UInt16,
        threshold: UInt8
    ) -> Data {
        var out = objectNETPrefix(nameIndex: nameIndex)
        out.appendUInt16(flags)
        out.append(threshold)
        return out
    }

    /// Full file: header, block payloads back to back, footer roots.
    static func file(
        blocks: [Block],
        strings: [String] = [],
        groups: [UInt32] = [],
        roots: [Int32] = [0]
    ) -> Data {
        var out = header(blocks: blocks, strings: strings, groups: groups)
        for block in blocks {
            out.append(block.data)
        }
        out.appendUInt32(UInt32(roots.count))
        for root in roots {
            out.appendUInt32(UInt32(bitPattern: root))
        }
        return out
    }
}
