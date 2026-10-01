// Shared NiObjectNET + NiAVObject prefix for scene-graph blocks, Skyrim streams
// only. Rotation is transposed on read so it applies to column vectors, as in
// MatrixMath. Layout: docs/formats/nif.md.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated extension BinaryReader {
    /// Three little-endian floats (nif.xml Vector3).
    public mutating func readVector3() throws -> SIMD3<Float> {
        try SIMD3(readFloat32(), readFloat32(), readFloat32())
    }
}

/// NiObjectNET field run: name, extra data refs (skipped), controller ref
/// (skipped). Property blocks (BSLightingShaderProperty, NiAlphaProperty)
/// start here directly; scene-graph objects continue with NiAVObject fields
/// (NIFObjectPrefix).
nonisolated public struct NIFObjectNET: Sendable {
    /// Resolved from the header string table. nil when unnamed (index -1) or
    /// the index is junk — lenient because vanilla string tables carry
    /// exporter garbage (docs/formats/nif.md) and a bad name must not reject
    /// the mesh.
    public let name: String?

    public init(reader: inout BinaryReader, header: NIFHeader) throws {
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
    }
}

nonisolated public struct NIFObjectPrefix: Sendable {
    /// See NIFObjectNET.name.
    public let name: String?
    public let flags: UInt32
    public let translation: SIMD3<Float>
    /// The node's rotation in the engine's convention: `R * v` on column
    /// vectors. Transposed on the way in, because NIF is a row-vector format
    /// (see `init`).
    public let rotation: simd_float3x3
    public let scale: Float
    /// bhk collision object ref; -1 = none.
    public let collisionRef: Int32

    /// Local transform `T * R * S` (column vectors, matches
    /// docs/decisions/coordinates.md).
    public var localTransform: float4x4 {
        float4x4(columns: (
            SIMD4<Float>(rotation.columns.0 * scale, 0),
            SIMD4<Float>(rotation.columns.1 * scale, 0),
            SIMD4<Float>(rotation.columns.2 * scale, 0),
            SIMD4<Float>(translation, 1)
        ))
    }

    public init(reader: inout BinaryReader, header: NIFHeader) throws {
        let streamVersion = header.bsStream?.version ?? 0
        guard streamVersion == 83 || streamVersion == 100 else {
            throw NIFError.unsupported(
                "scene-graph decode needs a Skyrim BS stream (83/100), got \(streamVersion)"
            )
        }

        name = try NIFObjectNET(reader: &reader, header: header).name

        flags = try reader.readUInt32()
        translation = try reader.readVector3()
        // NIF multiplies row vectors (`v * M`), so reading the column groups
        // as rows gives the transpose that works on column vectors. Skeletons
        // tear without it (docs/formats/nif.md, "Matrix33 is transposed").
        rotation = try simd_float3x3(rows: [
            reader.readVector3(),
            reader.readVector3(),
            reader.readVector3()
        ])
        scale = try reader.readFloat32()
        collisionRef = try Int32(bitPattern: reader.readUInt32())
    }
}
