// BSTriShape decode tests over synthetic in-code payloads (NIFFixture):
// interleaved BSVertexDataSSE records, half-float UVs, packed-byte normals,
// stride/data-size cross-checks. Layouts per NifTools nif.xml;
// docs/formats/nif.md.

import Foundation
@testable import opensky
import simd
import Testing

struct NIFTriShapeTests {
    private static let staticAttributes: UInt16 = 0x1B // vertex|uvs|normals|tangents
    private static let staticStrideDwords = 7 // 16 + 4 + 4 + 4 bytes

    private func header() throws -> NIFHeader {
        var reader = BinaryReader(NIFFixture.header())
        return try NIFHeader(reader: &reader)
    }

    /// One vertex|uvs|normals|tangents record: position + bitangent X float,
    /// two half UVs, packed normal + bitangent Y, packed tangent + bitangent Z.
    private func staticVertex(
        position: SIMD3<Float>,
        bitangentX: Float = 0,
        uv: SIMD2<Float> = .zero,
        normalBytes: [UInt8] = [128, 128, 255],
        bitangentYByte: UInt8 = 128,
        tangentBytes: [UInt8] = [255, 128, 128],
        bitangentZByte: UInt8 = 128
    ) -> Data {
        var out = Data()
        out.appendFloat32(position.x)
        out.appendFloat32(position.y)
        out.appendFloat32(position.z)
        out.appendFloat32(bitangentX)
        out.appendFloat16(uv.x)
        out.appendFloat16(uv.y)
        out.append(contentsOf: normalBytes)
        out.append(bitangentYByte)
        out.append(contentsOf: tangentBytes)
        out.append(bitangentZByte)
        return out
    }

    @Test func decodesSingleStaticTriShape() throws {
        let payload = NIFFixture.bsTriShape(
            prefix: NIFFixture.avObjectPrefix(nameIndex: 0),
            center: SIMD3(1, 2, 3),
            radius: 4,
            shaderPropertyRef: 2,
            alphaPropertyRef: 3,
            attributes: Self.staticAttributes,
            strideDwords: Self.staticStrideDwords,
            vertexRecords: [
                staticVertex(position: SIMD3(0, 0, 0), bitangentX: 0.5, uv: SIMD2(0.5, 1)),
                staticVertex(position: SIMD3(100, 0, 0)),
                staticVertex(position: SIMD3(0, 100, 0))
            ],
            triangles: [0, 1, 2]
        )
        let file = try NIFFile(data: NIFFixture.file(
            blocks: [.init("BSTriShape", payload)],
            strings: ["TestShape"]
        ))
        let shape = try NIFTriShape(data: file.blocks[0].data, header: file.header)

        #expect(shape.object.name == "TestShape")
        #expect(shape.boundingSphereCenter == SIMD3(1, 2, 3))
        #expect(shape.boundingSphereRadius == 4)
        #expect(shape.skinRef == -1)
        #expect(shape.shaderPropertyRef == 2)
        #expect(shape.alphaPropertyRef == 3)
        #expect(shape.attributes == [.vertex, .uvs, .normals, .tangents])
        #expect(shape.positions == [
            SIMD3(0, 0, 0), SIMD3(100, 0, 0), SIMD3(0, 100, 0)
        ])
        #expect(shape.indices == [0, 1, 2])
        // Half-float UVs decode exactly for representable values.
        #expect(shape.uvs[0] == SIMD2(0.5, 1))
        // normbyte remap: 255 -> 1, 128 -> 1/255, 0 -> -1.
        #expect(shape.normals.count == 3)
        #expect(abs(shape.normals[0].z - 1) < 1e-6)
        #expect(abs(shape.normals[0].x - 1 / 255) < 1e-6)
        #expect(abs(shape.tangents[0].x - 1) < 1e-6)
        // Bitangent reassembled from its split storage.
        #expect(abs(shape.bitangents[0].x - 0.5) < 1e-6)
        #expect(abs(shape.bitangents[0].y - 1 / 255) < 1e-6)
    }

    @Test func decodesHalfFloatEdgeValues() throws {
        var record = Data()
        record.appendFloat32(0)
        record.appendFloat32(0)
        record.appendFloat32(0)
        record.appendUInt32(0) // unused W (no tangents)
        record.appendUInt16(0x3C00) // 1.0
        record.appendUInt16(0xBC00) // -1.0
        let payload = NIFFixture.bsTriShape(
            attributes: 0x3, // vertex|uvs
            strideDwords: 5, // 16 + 4 bytes
            vertexRecords: [record]
        )
        let shape = try NIFTriShape(data: payload, header: header())
        #expect(shape.uvs == [SIMD2(1, -1)])
        #expect(shape.bitangents.isEmpty)
        #expect(shape.normals.isEmpty)
    }

    @Test func decodesSkinningDataAndReadsColors() throws {
        // vertex|uvs|colors|skinned: decode four half weights + byte indices
        // without shifting the following vertex's fields.
        var record = Data()
        record.appendFloat32(7)
        record.appendFloat32(8)
        record.appendFloat32(9)
        record.appendUInt32(0) // unused W
        record.appendUInt16(0) // uv
        record.appendUInt16(0)
        record.append(contentsOf: [255, 0, 255, 51]) // RGBA color
        record.appendFloat16(0.5)
        record.appendFloat16(0.25)
        record.appendFloat16(0.25)
        record.appendFloat16(0)
        record.append(contentsOf: [3, 2, 1, 0])
        let payload = NIFFixture.bsTriShape(
            attributes: 0x63, // vertex|uvs|colors|skinned
            strideDwords: 9, // 16 + 4 + 4 + 12 bytes
            vertexRecords: [record, record]
        )
        let shape = try NIFTriShape(data: payload, header: header())
        #expect(shape.positions == [SIMD3(7, 8, 9), SIMD3(7, 8, 9)])
        #expect(shape.colors.count == 2)
        #expect(shape.colors[0] == SIMD4(1, 0, 1, Float(51) / 255))
        #expect(shape.boneWeights[0] == SIMD4(0.5, 0.25, 0.25, 0))
        #expect(shape.boneIndices[0] == SIMD4(3, 2, 1, 0))
    }

    @Test func strideMismatchIsMalformed() throws {
        let payload = NIFFixture.bsTriShape(
            attributes: 0x1B,
            strideDwords: 5 // attributes imply 7
        )
        #expect(throws: NIFError.self) {
            try NIFTriShape(data: payload, header: header())
        }
    }

    @Test func dataSizeMismatchIsMalformed() throws {
        let payload = NIFFixture.bsTriShape(
            attributes: 0x3,
            strideDwords: 5,
            vertexRecords: [Data(count: 20)],
            dataSizeOverride: 99
        )
        #expect(throws: NIFError.self) {
            try NIFTriShape(data: payload, header: header())
        }
    }

    @Test func triangleIndexOutOfRangeIsMalformed() throws {
        let payload = NIFFixture.bsTriShape(
            attributes: 0x3,
            strideDwords: 5,
            vertexRecords: [Data(count: 20)],
            triangles: [0, 0, 7] // only 1 vertex
        )
        #expect(throws: NIFError.self) {
            try NIFTriShape(data: payload, header: header())
        }
    }

    @Test func zeroDataSizeYieldsEmptyGeometry() throws {
        let payload = NIFFixture.bsTriShape(
            attributes: Self.staticAttributes,
            strideDwords: Self.staticStrideDwords
        )
        let shape = try NIFTriShape(data: payload, header: header())
        #expect(shape.positions.isEmpty)
        #expect(shape.indices.isEmpty)
    }

    @Test func ignoresParticleTrailer() throws {
        let payload = NIFFixture.bsTriShape(
            attributes: 0x3,
            strideDwords: 5,
            vertexRecords: [Data(count: 20)],
            particleData: Data(count: 9)
        )
        let shape = try NIFTriShape(data: payload, header: header())
        #expect(shape.positions.count == 1)
    }

    @Test func dynamicShapeReplacesInheritedPositions() throws {
        let inherited = NIFFixture.bsTriShape(
            attributes: 0x3,
            strideDwords: 5,
            vertexRecords: [Data(count: 20), Data(count: 20)]
        )
        let payload = NIFFixture.bsDynamicTriShape(
            inherited: inherited,
            positions: [SIMD3(1, 2, 3), SIMD3(4, 5, 6)]
        )
        let shape = try NIFDynamicTriShape(data: payload, header: header()).shape

        #expect(shape.vertexCount == 2)
        #expect(shape.positions == [SIMD3(1, 2, 3), SIMD3(4, 5, 6)])
    }

    @Test func dynamicShapeRejectsWrongVertexByteCount() throws {
        let inherited = NIFFixture.bsTriShape(
            attributes: 0x3,
            strideDwords: 5,
            vertexRecords: [Data(count: 20)]
        )
        let payload = NIFFixture.bsDynamicTriShape(
            inherited: inherited,
            positions: [SIMD3.zero],
            byteCountOverride: 12
        )
        #expect(throws: NIFError.self) {
            try NIFDynamicTriShape(data: payload, header: header())
        }
    }
}
