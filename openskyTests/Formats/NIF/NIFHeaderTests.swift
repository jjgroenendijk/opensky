// NIF header decode tests over synthetic in-code files (NIFFixture).

import Foundation
@testable import opensky
import Testing

struct NIFHeaderTests {
    private func parse(_ data: Data) throws -> NIFHeader {
        var reader = BinaryReader(data)
        return try NIFHeader(reader: &reader)
    }

    @Test func decodesFullHeader() throws {
        let data = NIFFixture.header(
            blocks: [
                .init("NiNode", Data(count: 20)),
                .init("BSTriShape", Data(count: 8)),
                .init("NiNode", Data(count: 4))
            ],
            strings: ["Scene Root", "WRCastle"],
            groups: [7, 9]
        )
        let header = try parse(data)
        #expect(header.versionLine == NIFFixture.versionLine)
        #expect(header.version == NIFHeader.supportedVersion)
        #expect(header.userVersion == 12)
        #expect(header.blockCount == 3)
        #expect(header.blockTypes == ["NiNode", "BSTriShape"])
        #expect(header.blockTypeIndices == [0, 1, 0])
        #expect(header.blockSizes == [20, 8, 4])
        #expect(header.strings == ["Scene Root", "WRCastle"])
        #expect(header.groups == [7, 9])
        #expect(header.blockDataOffset == data.count)
    }

    @Test func decodesBSStream() throws {
        let header = try parse(NIFFixture.header(bsVersion: 100))
        let stream = try #require(header.bsStream)
        #expect(stream.version == 100)
        #expect(stream.author == "OpenSky Tests")
        #expect(stream.processScript.isEmpty)
        #expect(stream.exportScript.isEmpty)
    }

    @Test func skipsBSStreamForLowUserVersion() throws {
        let header = try parse(NIFFixture.header(userVersion: 0))
        #expect(header.userVersion == 0)
        #expect(header.bsStream == nil)
    }

    @Test func masksPhysXFlagOnBlockTypeIndex() throws {
        let data = NIFFixture.header(blocks: [.init("NiPhysXProp", Data(), physXFlag: true)])
        let header = try parse(data)
        #expect(header.blockTypeIndices == [0])
    }

    @Test func rejectsUnsupportedVersion() throws {
        let data = NIFFixture.header(version: 0x1400_0005) // 20.0.0.5
        #expect(throws: NIFError.self) { try parse(data) }
    }

    @Test func rejectsBigEndian() throws {
        #expect(throws: NIFError.unsupported("big-endian NIF")) {
            try parse(NIFFixture.header(endian: 0))
        }
    }

    @Test func rejectsVersionLineWithoutNewline() throws {
        let data = Data(repeating: UInt8(ascii: "x"), count: 256)
        #expect(throws: NIFError.malformed("header version line missing newline terminator")) {
            try parse(data)
        }
    }

    @Test func rejectsBlockTypeIndexOutOfRange() throws {
        // One block, one type, but the stored index points past the table.
        var data = Data(NIFFixture.versionLine.utf8)
        data.append(0x0A)
        data.appendUInt32(NIFFixture.version)
        data.append(1)
        data.appendUInt32(0) // user version 0 -> no BS stream
        data.appendUInt32(1) // block count
        data.appendUInt16(1) // block type count
        data.append(NIFFixture.sizedString("NiNode"))
        data.appendUInt16(5) // out-of-range type index
        #expect(throws: NIFError.malformed("block 0 type index 5 out of range (1 types)")) {
            try parse(data)
        }
    }

    @Test func decodesGarbageStringTableEntryLossily() throws {
        // Vanilla meshes carry exporter junk in the string table (observed:
        // uninitialized memory with 0x90, undefined in cp1252). Must not
        // reject the file.
        var data = Data(NIFFixture.versionLine.utf8)
        data.append(0x0A)
        data.appendUInt32(NIFFixture.version)
        data.append(1)
        data.appendUInt32(0) // user version 0 -> no BS stream
        data.appendUInt32(0) // block count
        data.appendUInt16(0) // block type count
        data.appendUInt32(1) // string count
        data.appendUInt32(4) // max string length
        data.append(NIFFixture.sizedString(raw: Data([0x0C, 0x90, 0x29, 0x7B])))
        data.appendUInt32(0) // group count
        var reader = BinaryReader(data)
        let header = try NIFHeader(reader: &reader)
        #expect(header.strings.count == 1)
        #expect(!header.strings[0].isEmpty)
    }

    @Test func throwsOnTruncatedHeader() throws {
        let data = NIFFixture.header(blocks: [.init("NiNode", Data(count: 16))])
        #expect(throws: (any Error).self) { try parse(data.prefix(data.count - 6)) }
    }
}
