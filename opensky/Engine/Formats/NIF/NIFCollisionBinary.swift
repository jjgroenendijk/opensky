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
