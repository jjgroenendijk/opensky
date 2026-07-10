// Unit tests for BinaryReader bounds checking and string decoding.

import Foundation
@testable import opensky
import Testing

struct BinaryReaderTests {
    @Test func readsLittleEndianIntegers() throws {
        var reader = BinaryReader(Data([0x01, 0x02, 0x03, 0x04, 0xFF, 0x00, 0x00, 0x00]))
        #expect(try reader.readUInt32() == 0x0403_0201)
        #expect(try reader.readUInt32() == 0xFF)
        #expect(reader.bytesRemaining == 0)
    }

    @Test func readsFloat32() throws {
        var data = Data()
        data.appendFloat32(1.5)
        data.appendFloat32(-0.25)
        var reader = BinaryReader(data)
        #expect(try reader.readFloat32() == 1.5)
        #expect(try reader.readFloat32() == -0.25)
    }

    @Test func readPastEndThrows() {
        var reader = BinaryReader(Data([0x01]))
        #expect(throws: BinaryReaderError.outOfBounds(offset: 0, count: 4, available: 1)) {
            try reader.readUInt32()
        }
    }

    @Test func readsZString() throws {
        var reader = BinaryReader(Data("abc\0def\0".utf8))
        #expect(try reader.readZString() == "abc")
        #expect(try reader.readZString() == "def")
    }

    @Test func unterminatedZStringThrows() {
        var reader = BinaryReader(Data("abc".utf8))
        #expect(throws: BinaryReaderError.unterminatedString(offset: 0)) {
            try reader.readZString()
        }
    }

    @Test func readsBZString() throws {
        // Length prefix counts the trailing null.
        var reader = BinaryReader(Data([0x04]) + Data("abc\0".utf8))
        #expect(try reader.readBZString() == "abc")
        #expect(reader.bytesRemaining == 0)
    }

    @Test func readsBString() throws {
        // Length prefix, no terminator.
        var reader = BinaryReader(Data([0x03]) + Data("abc".utf8))
        #expect(try reader.readBString() == "abc")
        #expect(reader.bytesRemaining == 0)
    }

    @Test func decodesWindows1252() throws {
        // 0xE9 = 'é' in windows-1252; invalid as UTF-8.
        var reader = BinaryReader(Data([0xE9, 0x00]))
        #expect(try reader.readZString() == "é")
    }
}
