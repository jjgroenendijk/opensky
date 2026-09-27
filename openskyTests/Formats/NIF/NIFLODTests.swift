import Foundation
@testable import opensky
import simd
import Testing

struct NIFLODTests {
    private static let attributes: UInt16 = 0x3

    private func header(strings: [String] = []) throws -> NIFHeader {
        var reader = BinaryReader(NIFFixture.header(strings: strings))
        return try NIFHeader(reader: &reader)
    }

    private func shape(nameIndex: UInt32 = .max) -> Data {
        let vertex = Data(count: 20)
        return NIFFixture.bsTriShape(
            prefix: NIFFixture.avObjectPrefix(nameIndex: nameIndex),
            attributes: Self.attributes,
            strideDwords: 5,
            vertexRecords: [vertex, vertex, vertex],
            triangles: [0, 1, 2]
        )
    }

    private func multiBoundNode(
        nameIndex: UInt32,
        children: [Int32],
        boundRef: Int32 = -1
    ) -> Data {
        var data = NIFFixture.niNode(
            prefix: NIFFixture.avObjectPrefix(nameIndex: nameIndex),
            children: children
        )
        data.appendUInt32(UInt32(bitPattern: boundRef))
        data.appendUInt32(1)
        return data
    }

    @Test func decodesMultiBoundBlocks() throws {
        let node = try NIFMultiBoundNode(
            data: multiBoundNode(nameIndex: 0, children: [2, -1], boundRef: 4),
            header: header(strings: ["chunk"])
        )
        #expect(node.object.name == "chunk")
        #expect(node.children == [2, -1])
        #expect(node.multiBoundRef == 4)
        #expect(node.cullingMode == 1)

        var bound = Data()
        bound.appendUInt32(7)
        #expect(try NIFMultiBound(data: bound).dataRef == 7)

        var aabb = Data()
        for value: Float in [1, 2, 3, 4, 5, 6] {
            aabb.appendFloat32(value)
        }
        let parsed = try NIFMultiBoundAABB(data: aabb)
        #expect(parsed.center == SIMD3(1, 2, 3))
        #expect(parsed.extent == SIMD3(4, 5, 6))
    }

    @Test func decodesSubIndexSegmentsAndFlattensShape() throws {
        var payload = shape()
        payload.appendUInt32(1)
        payload.append(0xA5)
        payload.appendUInt32(0)
        payload.appendUInt32(1)
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("BSSubIndexTriShape", payload)
        ]))
        let parsed = try NIFSubIndexTriShape(data: payload, header: file.header)
        #expect(parsed.segments == [.init(flags: 0xA5, startIndex: 0, primitiveCount: 1)])
        #expect(try file.model().meshes.count == 1)
    }

    @Test func rejectsSubIndexSegmentOutsideTriangles() throws {
        var payload = shape()
        payload.appendUInt32(1)
        payload.append(0)
        payload.appendUInt32(3)
        payload.appendUInt32(1)
        #expect(throws: NIFError.self) {
            try NIFSubIndexTriShape(data: payload, header: header())
        }
    }

    @Test func waterSubtreeIsSkipped() throws {
        let file = try NIFFile(data: NIFFixture.file(
            blocks: [
                .init("BSMultiBoundNode", multiBoundNode(nameIndex: 0, children: [1, 2])),
                .init("BSTriShape", shape(nameIndex: 1)),
                .init("BSMultiBoundNode", multiBoundNode(nameIndex: 2, children: [3])),
                .init("BSTriShape", shape(nameIndex: 3))
            ],
            strings: ["chunk", "land", "WATER", "water shape"]
        ))
        let model = try file.model()
        #expect(model.meshes.count == 1)
        #expect(model.meshes[0].name == "land")
    }
}
