// NIF container block-walk + footer tests over synthetic in-code files
// (NIFFixture). Unknown block types must be carried, not crash the walk.

import Foundation
@testable import opensky
import Testing

struct NIFFileTests {
    @Test func walksBlocksBySizeAndSlicesPayloads() throws {
        let node = Data([0xAA, 0xBB, 0xCC])
        let shape = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", node),
            .init("BSTriShape", shape)
        ]))
        #expect(file.blocks.count == 2)
        #expect(file.blocks[0].typeName == "NiNode")
        #expect(file.blocks[0].data == node)
        #expect(file.blocks[1].typeName == "BSTriShape")
        #expect(file.blocks[1].data == shape)
    }

    @Test func skipsUnknownBlockTypesAndKeepsWalking() throws {
        // Types the engine will never decode still walk cleanly by size.
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("bhkCollisionObject", Data(count: 12)),
            .init("NiControllerManager", Data(count: 40)),
            .init("BSTriShape", Data([0x7F]))
        ]))
        #expect(file.blocks.map(\.typeName) == [
            "bhkCollisionObject", "NiControllerManager", "BSTriShape"
        ])
        #expect(file.blocks[2].data == Data([0x7F]))
    }

    @Test func readsFooterRoots() throws {
        let file = try NIFFile(data: NIFFixture.file(
            blocks: [.init("NiNode", Data(count: 4))],
            roots: [0, -1]
        ))
        #expect(file.roots == [0, -1])
    }

    @Test func countsBlockTypes() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", Data(count: 1)),
            .init("BSTriShape", Data(count: 1)),
            .init("NiNode", Data(count: 1))
        ]))
        #expect(file.blockTypeCounts() == ["NiNode": 2, "BSTriShape": 1])
    }

    @Test func throwsOnBlockExtendingPastEndOfFile() throws {
        // Header promises 64 bytes for block 0; file body carries none.
        var data = NIFFixture.header(blocks: [.init("NiNode", Data(count: 64))])
        data.appendUInt32(0) // footer root count directly after header
        #expect(throws: NIFError.malformed(
            "block 0 (NiNode, 64 bytes) extends past end of file"
        )) {
            _ = try NIFFile(data: data)
        }
    }

    @Test func throwsOnTruncatedFooter() throws {
        var data = NIFFixture.header(blocks: [.init("NiNode", Data(count: 2))])
        data.append(Data(count: 2)) // block payload, then no footer
        #expect(throws: NIFError.malformed("truncated footer")) {
            _ = try NIFFile(data: data)
        }
    }

    @Test func emptyFileHasNoBlocksAndNoRoots() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [], roots: []))
        #expect(file.blocks.isEmpty)
        #expect(file.roots.isEmpty)
        #expect(file.header.blockCount == 0)
    }
}
