// Unit tests for the SWF container decoder. Fixtures are synthetic SWF blobs
// built in code via SWFFixture — never extracted game files (AGENTS.md "Legal
// & IP boundary").

import Foundation
@testable import opensky
import Testing

struct SWFFileTests {
    @Test func parsesUncompressedHeaderFields() throws {
        var fixture = SWFFixture()
        fixture.version = 6
        fixture.xMin = -20
        fixture.xMax = 8000
        fixture.yMin = 0
        fixture.yMax = 6000
        fixture.frameRateFixed = UInt16(30 << 8) // 30 fps as 8.8 fixed point
        fixture.frameCount = 5
        fixture.tags = [.init(code: 26, body: Data([1, 2, 3]))] // PlaceObject2
        let bytes = fixture.build()

        let swf = try SWFFile(data: bytes)
        #expect(swf.version == 6)
        #expect(swf.compression == .none)
        #expect(swf.fileLength == bytes.count)
        #expect(swf.frameSize == SWFRect(xMin: -20, xMax: 8000, yMin: 0, yMax: 6000))
        #expect(swf.frameRate == 30)
        #expect(swf.frameCount == 5)
        #expect(swf.tags.count == 2) // PlaceObject2 + End
        #expect(swf.tags[0] == SWFTag(code: 26, body: Data([1, 2, 3])))
        #expect(swf.tags.last?.code == 0)
    }

    @Test func parsesCompressedRoundTrip() throws {
        var fixture = SWFFixture()
        fixture.signature = "CWS"
        fixture.version = 8
        fixture.frameCount = 3
        fixture.tags = [.init(code: 9, body: Data([0x11, 0x22, 0x33]))] // SetBackgroundColor

        let swf = try SWFFile(data: fixture.build())
        #expect(swf.compression == .zlib)
        #expect(swf.version == 8)
        #expect(swf.frameCount == 3)
        #expect(swf.tags[0] == SWFTag(code: 9, body: Data([0x11, 0x22, 0x33])))
        #expect(swf.tags.last?.code == 0)
    }

    @Test func readsLongFormTag() throws {
        var fixture = SWFFixture()
        let big = Data(repeating: 0xAB, count: 100) // >= 0x3F forces UI32 length
        fixture.tags = [.init(code: 2, body: big)] // DefineShape

        let swf = try SWFFile(data: fixture.build())
        #expect(swf.tags[0] == SWFTag(code: 2, body: big))
        #expect(swf.tags[0].body.count == 100)
    }

    @Test func stopsAtEndTagIgnoringTrailingBytes() throws {
        var fixture = SWFFixture()
        fixture.tags = [.init(code: 1, body: Data())] // ShowFrame
        var bytes = fixture.build()
        bytes.append(contentsOf: [0xDE, 0xAD, 0xBE, 0xEF]) // junk after End

        let swf = try SWFFile(data: bytes)
        #expect(swf.tags.contains(SWFTag(code: 1, body: Data())))
        #expect(swf.tags.last?.code == 0)
    }

    @Test func passesUnknownTagThrough() throws {
        var fixture = SWFFixture()
        fixture.tags = [.init(code: 1002, body: Data([0xAA]))] // GFx extension range

        let swf = try SWFFile(data: fixture.build())
        #expect(swf.tags[0] == SWFTag(code: 1002, body: Data([0xAA])))
        #expect(SWFTagName.name(forCode: 1002) == nil)
    }

    @Test func rejectsUnknownSignature() {
        var fixture = SWFFixture()
        fixture.signature = "XYZ"
        #expect(throws: SWFError.notASWF) {
            _ = try SWFFile(data: fixture.build())
        }
    }

    @Test func rejectsLZMACompression() {
        var fixture = SWFFixture()
        fixture.signature = "ZWS"
        #expect(throws: SWFError.unsupportedCompression(signature: "ZWS")) {
            _ = try SWFFile(data: fixture.build())
        }
    }

    @Test func rejectsTruncatedHeader() {
        let bytes = Data("FWS".utf8) + Data([6, 0x10]) // length field cut short
        #expect(throws: (any Error).self) {
            _ = try SWFFile(data: bytes)
        }
    }

    @Test func rejectsTruncatedTagBody() {
        var fixture = SWFFixture()
        fixture.appendEnd = false
        fixture.tags = [.init(code: 2, body: Data(count: 100))]
        let bytes = fixture.build().prefix(fixture.build().count - 40)
        #expect(throws: (any Error).self) {
            _ = try SWFFile(data: Data(bytes))
        }
    }

    @Test func rejectsRectRunningPastEnd() {
        // Nbits = 31 (top 5 bits of 0xFF), but only one body byte follows, so
        // the first SB[31] field overruns.
        var bytes = Data("FWS".utf8)
        bytes.append(6)
        bytes.appendUInt32(9)
        bytes.append(0xFF)
        #expect(throws: (any Error).self) {
            _ = try SWFFile(data: bytes)
        }
    }

    @Test func mapsKnownTagCodesToNames() {
        #expect(SWFTagName.name(forCode: 0) == "End")
        #expect(SWFTagName.name(forCode: 26) == "PlaceObject2")
        #expect(SWFTagName.name(forCode: 93) == "EnableTelemetry")
        #expect(SWFTagName.isKnown(2))
        #expect(!SWFTagName.isKnown(1002)) // GFx extension, not in the Adobe spec
    }
}

struct SWFBitReaderTests {
    @Test func readsUnsignedFields() throws {
        var reader = SWFBitReader(Data([0b1011_0010]))
        #expect(try reader.readUB(3) == 0b101)
        #expect(try reader.readUB(5) == 0b10010)
    }

    @Test func signExtendsNegativeFields() throws {
        var reader = SWFBitReader(Data([0b1110_1000])) // 5-bit 0b11101 == -3
        #expect(try reader.readSB(5) == -3)
    }

    @Test func alignsToByteBoundary() throws {
        var reader = SWFBitReader(Data([0xFF, 0xAB]))
        _ = try reader.readUB(3)
        reader.align()
        #expect(reader.byteOffset == 1)
        #expect(try reader.readUB(8) == 0xAB)
    }

    @Test func rejectsOverread() {
        var reader = SWFBitReader(Data([0x00]))
        #expect(throws: SWFBitReaderError.self) {
            _ = try reader.readUB(9)
        }
    }
}
