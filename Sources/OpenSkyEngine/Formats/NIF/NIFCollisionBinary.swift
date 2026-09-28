// Shared little-endian primitives for Skyrim bhk block decoders.
// Matrix44 uses nif.xml column-major field order; Havok translations are
// converted to engine units while rotations/scales remain unitless.

import Foundation
import simd

nonisolated extension BinaryReader {
    mutating func readNIFRef() throws -> Int32 {
        try Int32(bitPattern: readUInt32())
    }

    mutating func readVector4() throws -> SIMD4<Float> {
        try SIMD4(readFloat32(), readFloat32(), readFloat32(), readFloat32())
    }

    mutating func readCollisionFilter() throws -> NIFCollisionFilter {
        try NIFCollisionFilter(
            layer: readUInt8(),
            flags: readUInt8(),
            group: readUInt16()
        )
    }

    /// A Havok position stored as `Vector4`: XYZ converted to engine units,
    /// W discarded (nif.xml keeps it only for 16-byte alignment).
    mutating func readHavokPoint() throws -> SIMD3<Float> {
        try readVector4().xyz * NIFCollisionModel.havokToEngineScale
    }

    /// A Havok direction stored as `Vector4`: unitless, so no conversion.
    mutating func readHavokAxis() throws -> SIMD3<Float> {
        try readVector4().xyz
    }

    /// nif.xml `bool` is one byte from stream 4.1.0.1 on, which covers every
    /// Skyrim NIF. Any non-zero byte is true.
    mutating func readHavokBool() throws -> Bool {
        try readUInt8() != 0
    }

    /// nif.xml `hkMatrix3`: three rows of four floats, the fourth of each
    /// unused. Transposed on read so the result applies to column vectors,
    /// matching `NIFObjectPrefix.rotation` and MatrixMath.
    mutating func readHavokMatrix3() throws -> float3x3 {
        let rows = try (readVector4().xyz, readVector4().xyz, readVector4().xyz)
        return float3x3(rows: [rows.0, rows.1, rows.2])
    }

    mutating func readCollisionMatrix() throws -> float4x4 {
        var columns = try (
            readVector4(),
            readVector4(),
            readVector4(),
            readVector4()
        )
        let scale = NIFCollisionModel.havokToEngineScale
        columns.3.x *= scale
        columns.3.y *= scale
        columns.3.z *= scale
        return float4x4(columns: columns)
    }

    mutating func readHavokTransform() throws -> float4x4 {
        let translation = try readVector4()
        let quaternion = try readVector4()
        let length = simd_length(quaternion)
        guard length.isFinite, length > .ulpOfOne else {
            throw NIFError.malformed("zero or non-finite Havok quaternion")
        }
        let rotation = float3x3(simd_quatf(vector: quaternion / length))
        let engineTranslation = translation.xyz * NIFCollisionModel.havokToEngineScale
        return float4x4(columns: (
            SIMD4(rotation.columns.0, 0),
            SIMD4(rotation.columns.1, 0),
            SIMD4(rotation.columns.2, 0),
            SIMD4(engineTranslation, 1)
        ))
    }
}

nonisolated extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        SIMD3(x, y, z)
    }
}
