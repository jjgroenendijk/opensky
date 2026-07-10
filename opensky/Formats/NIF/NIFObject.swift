// Shared NiObjectNET + NiAVObject field prefix for scene-graph blocks
// (NiNode lineage, BSTriShape). Skyrim streams only: flags are uint32
// (BS stream > 26) and the NiAVObject property list is absent (> 34), so
// name, extra data, controller, flags, transform, collision follow back to
// back. Rotation is stored column-major (nif.xml Matrix33) and applies to
// column vectors — same convention as MatrixMath.
//
// Reference: NifTools nif.xml (NiObjectNET, NiAVObject, Matrix33, Vector3).
//   https://github.com/niftools/nifxml/blob/develop/nif.xml
// Layout documented in docs/formats/nif.md.

import Foundation
import simd

nonisolated extension BinaryReader {
    /// Three little-endian floats (nif.xml Vector3).
    mutating func readVector3() throws -> SIMD3<Float> {
        try SIMD3(readFloat32(), readFloat32(), readFloat32())
    }
}

nonisolated struct NIFObjectPrefix {
    /// Resolved from the header string table. nil when unnamed (index -1) or
    /// the index is junk — lenient because vanilla string tables carry
    /// exporter garbage (docs/formats/nif.md) and a bad name must not reject
    /// the mesh.
    let name: String?
    let flags: UInt32
    let translation: SIMD3<Float>
    /// Rotation straight off the file: column-major, `R * v` semantics.
    let rotation: simd_float3x3
    let scale: Float
    /// bhk collision object ref; -1 = none. Recorded, never followed (M2
    /// skips collision).
    let collisionRef: Int32

    /// Local transform `T * R * S` (column vectors, matches
    /// docs/decisions/coordinates.md).
    var localTransform: float4x4 {
        float4x4(columns: (
            SIMD4<Float>(rotation.columns.0 * scale, 0),
            SIMD4<Float>(rotation.columns.1 * scale, 0),
            SIMD4<Float>(rotation.columns.2 * scale, 0),
            SIMD4<Float>(translation, 1)
        ))
    }

    init(reader: inout BinaryReader, header: NIFHeader) throws {
        let streamVersion = header.bsStream?.version ?? 0
        guard streamVersion == 83 || streamVersion == 100 else {
            throw NIFError.unsupported(
                "scene-graph decode needs a Skyrim BS stream (83/100), got \(streamVersion)"
            )
        }

        let nameIndex = try reader.readUInt32()
        if nameIndex != .max, Int(nameIndex) < header.strings.count {
            name = header.strings[Int(nameIndex)]
        } else {
            name = nil
        }

        let extraDataCount = try Int(reader.readUInt32())
        guard extraDataCount * 4 <= reader.bytesRemaining else {
            throw NIFError.malformed(
                "extra data count \(extraDataCount) exceeds block size"
            )
        }
        reader.skip(extraDataCount * 4) // NiExtraData refs, unused
        reader.skip(4) // NiTimeController ref, unused (animation skipped)

        flags = try reader.readUInt32()
        translation = try reader.readVector3()
        // File order m11 m21 m31 | m12 m22 m32 | m13 m23 m33 — one column
        // per group of three.
        rotation = try simd_float3x3(columns: (
            reader.readVector3(),
            reader.readVector3(),
            reader.readVector3()
        ))
        scale = try reader.readFloat32()
        collisionRef = try Int32(bitPattern: reader.readUInt32())
    }
}
