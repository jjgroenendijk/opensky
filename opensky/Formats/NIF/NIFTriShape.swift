// BSTriShape: Skyrim SE static geometry. AV-object prefix, bounding sphere,
// skin/shader/alpha property refs, then a BSVertexDesc-driven interleaved
// vertex array and a uint16 triangle list. SSE variant only (BS stream 100):
// vertex records are BSVertexDataSSE, where positions are always full floats
// — unlike FO4's BSVertexData, which packs them as halfs behind the
// full-precision flag. Halfs remain in UVs; normals/tangents/bitangent Y+Z
// are normalized bytes.
//
// Reference: NifTools nif.xml (BSTriShape, BSVertexDesc, VertexAttribute,
// BSVertexDataSSE, NiBound, Triangle, HalfTexCoord, ByteVector3).
//   https://github.com/niftools/nifxml/blob/develop/nif.xml
// normbyte remap ((byte / 255) * 2 - 1) matches NifSkope/nifly, the
// reference implementations for these packed fields.
// Layout documented in docs/formats/nif.md.

import Foundation
import simd

nonisolated struct NIFTriShape {
    /// nif.xml VertexAttribute bits, stored at bits 44+ of BSVertexDesc.
    struct VertexAttributes: OptionSet {
        let rawValue: UInt16

        static let vertex = Self(rawValue: 1 << 0)
        static let uvs = Self(rawValue: 1 << 1)
        static let uvs2 = Self(rawValue: 1 << 2)
        static let normals = Self(rawValue: 1 << 3)
        static let tangents = Self(rawValue: 1 << 4)
        static let vertexColors = Self(rawValue: 1 << 5)
        static let skinned = Self(rawValue: 1 << 6)
        static let landData = Self(rawValue: 1 << 7)
        static let eyeData = Self(rawValue: 1 << 8)
        static let instance = Self(rawValue: 1 << 9)
        /// Ignored by the SSE record layout: positions are always full floats.
        static let fullPrecision = Self(rawValue: 1 << 10)
    }

    let object: NIFObjectPrefix
    /// nif.xml NiBound: precomputed culling sphere in shape-local space.
    let boundingSphereCenter: SIMD3<Float>
    let boundingSphereRadius: Float
    /// -1 = static geometry; >= 0 means skinned (skipped for M2).
    let skinRef: Int32
    let shaderPropertyRef: Int32
    let alphaPropertyRef: Int32
    let attributes: VertexAttributes
    let positions: [SIMD3<Float>]
    let uvs: [SIMD2<Float>]
    let normals: [SIMD3<Float>]
    let tangents: [SIMD3<Float>]
    /// Assembled from the split storage (X beside position, Y beside normal,
    /// Z beside tangent); present only when all three attributes are.
    let bitangents: [SIMD3<Float>]
    /// RGBA in [0, 1].
    let colors: [SIMD4<Float>]
    /// Flat triangle list, three indices each, all < positions.count.
    let indices: [UInt16]

    init(data: Data, header: NIFHeader) throws {
        var reader = BinaryReader(data)
        object = try NIFObjectPrefix(reader: &reader, header: header)
        guard header.bsStream?.version == 100 else {
            // Stream 83 (LE) predates BSTriShape; FO4 records differ.
            throw NIFError.unsupported("BSTriShape outside an SSE stream (BS 100)")
        }

        boundingSphereCenter = try reader.readVector3()
        boundingSphereRadius = try reader.readFloat32()
        skinRef = try Int32(bitPattern: reader.readUInt32())
        shaderPropertyRef = try Int32(bitPattern: reader.readUInt32())
        alphaPropertyRef = try Int32(bitPattern: reader.readUInt32())

        let desc = try reader.readUInt64()
        let triangleCount = try Int(reader.readUInt16()) // ushort: BS < 130
        let vertexCount = try Int(reader.readUInt16())
        let dataSize = try Int(reader.readUInt32())

        let attributes = VertexAttributes(rawValue: UInt16((desc >> 44) & 0x7FF))
        self.attributes = attributes

        // Cross-check the desc's stride nibble (dwords) against the stride
        // the attribute flags imply — a mismatch means a layout this decoder
        // does not model (e.g. land data) and byte-misaligned reads.
        let stride = Self.stride(for: attributes)
        let strideDwords = Int(desc & 0xF)
        guard stride == strideDwords * 4 else {
            throw NIFError.malformed(
                "vertex stride \(strideDwords * 4) does not match attributes "
                    + "0x\(String(attributes.rawValue, radix: 16)) (expected \(stride))"
            )
        }
        // nif.xml: Data Size = stride * vertices + 6 * triangles; vertex and
        // triangle arrays exist only when it is non-zero.
        guard dataSize == 0 || dataSize == vertexCount * stride + triangleCount * 6 else {
            throw NIFError.malformed(
                "data size \(dataSize) != \(vertexCount) vertices * \(stride) "
                    + "+ \(triangleCount) triangles * 6"
            )
        }

        if dataSize > 0 {
            let arrays = try Self.readVertexRecords(
                &reader,
                attributes: attributes,
                count: vertexCount
            )
            positions = arrays.positions
            uvs = arrays.uvs
            normals = arrays.normals
            tangents = arrays.tangents
            bitangents = arrays.bitangents
            colors = arrays.colors
            indices = try Self.readTriangles(
                &reader,
                triangleCount: triangleCount,
                vertexCount: vertexCount
            )
        } else {
            positions = []
            uvs = []
            normals = []
            tangents = []
            bitangents = []
            colors = []
            indices = []
        }

        // SSE-only trailer: particle-deformed copy of the geometry. The size
        // field is always present; the copy itself is ignored (M2 statics).
        _ = try reader.readUInt32()
    }

    private struct VertexArrays {
        var positions: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var normals: [SIMD3<Float>] = []
        var tangents: [SIMD3<Float>] = []
        var bitangents: [SIMD3<Float>] = []
        var colors: [SIMD4<Float>] = []
    }

    private static func readVertexRecords(
        _ reader: inout BinaryReader,
        attributes: VertexAttributes,
        count: Int
    ) throws -> VertexArrays {
        var arrays = VertexArrays()
        arrays.positions.reserveCapacity(count)
        let assembleBitangents = attributes.contains([.vertex, .normals, .tangents])
        for _ in 0 ..< count {
            var bitangent = SIMD3<Float>.zero
            if attributes.contains(.vertex) {
                try arrays.positions.append(reader.readVector3())
                if attributes.contains(.tangents) {
                    bitangent.x = try reader.readFloat32()
                } else {
                    reader.skip(4) // unused W
                }
            }
            if attributes.contains(.uvs) {
                try arrays.uvs.append(SIMD2(readHalf(&reader), readHalf(&reader)))
            }
            if attributes.contains(.normals) {
                try arrays.normals.append(readByteVector3(&reader))
                bitangent.y = try readNormByte(&reader)
                if attributes.contains(.tangents) {
                    try arrays.tangents.append(readByteVector3(&reader))
                    bitangent.z = try readNormByte(&reader)
                }
            }
            if assembleBitangents {
                arrays.bitangents.append(bitangent)
            }
            if attributes.contains(.vertexColors) {
                try arrays.colors.append(readByteColor4(&reader))
            }
            if attributes.contains(.skinned) {
                reader.skip(12) // 4 half weights + 4 byte bone indices
            }
            if attributes.contains(.eyeData) {
                reader.skip(4)
            }
        }
        return arrays
    }

    private static func readTriangles(
        _ reader: inout BinaryReader,
        triangleCount: Int,
        vertexCount: Int
    ) throws -> [UInt16] {
        var indices: [UInt16] = []
        indices.reserveCapacity(triangleCount * 3)
        for _ in 0 ..< triangleCount * 3 {
            let index = try reader.readUInt16()
            guard Int(index) < vertexCount else {
                throw NIFError.malformed(
                    "triangle index \(index) out of range (\(vertexCount) vertices)"
                )
            }
            indices.append(index)
        }
        return indices
    }

    /// Per-vertex byte stride the attribute flags imply (BSVertexDataSSE
    /// field conditions; position block is 16 bytes with either bitangent X
    /// or unused W as its fourth component).
    private static func stride(for attributes: VertexAttributes) -> Int {
        var stride = 0
        if attributes.contains(.vertex) {
            stride += 16
        }
        if attributes.contains(.uvs) {
            stride += 4
        }
        if attributes.contains(.normals) {
            stride += 4
        }
        if attributes.contains([.normals, .tangents]) {
            stride += 4
        }
        if attributes.contains(.vertexColors) {
            stride += 4
        }
        if attributes.contains(.skinned) {
            stride += 12
        }
        if attributes.contains(.eyeData) {
            stride += 4
        }
        return stride
    }

    /// IEEE 754 half-precision float (nif.xml hfloat).
    private static func readHalf(_ reader: inout BinaryReader) throws -> Float {
        try Float(Float16(bitPattern: reader.readUInt16()))
    }

    /// nif.xml normbyte: [-1, 1] stored as an unsigned byte.
    private static func readNormByte(_ reader: inout BinaryReader) throws -> Float {
        try Float(reader.readUInt8()) / 255 * 2 - 1
    }

    private static func readByteVector3(
        _ reader: inout BinaryReader
    ) throws -> SIMD3<Float> {
        try SIMD3(
            readNormByte(&reader),
            readNormByte(&reader),
            readNormByte(&reader)
        )
    }

    /// RGBA bytes, each remapped to [0, 1].
    private static func readByteColor4(
        _ reader: inout BinaryReader
    ) throws -> SIMD4<Float> {
        let bytes = try reader.read(count: 4)
        return SIMD4(
            Float(bytes[bytes.startIndex]) / 255,
            Float(bytes[bytes.startIndex + 1]) / 255,
            Float(bytes[bytes.startIndex + 2]) / 255,
            Float(bytes[bytes.startIndex + 3]) / 255
        )
    }
}
