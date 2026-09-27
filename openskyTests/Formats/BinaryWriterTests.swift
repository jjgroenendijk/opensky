// Unit tests for BinaryWriter byte ordering, string encoding, and round-trip
// through BinaryReader.

import Foundation
@testable import opensky
import Testing

struct BinaryWriterTests {
    @Test func writesLittleEndianUInt8() {
        var writer = BinaryWriter()
        writer.writeUInt8(0xAB)
        #expect(writer.data == Data([0xAB]))
        #expect(writer.count == 1)
    }

    @Test func writesLittleEndianUInt16() {
        var writer = BinaryWriter()
        writer.writeUInt16(0x0201)
        #expect(writer.data == Data([0x01, 0x02]))
    }

    @Test func writesLittleEndianUInt32() {
        var writer = BinaryWriter()
        writer.writeUInt32(0x0403_0201)
        #expect(writer.data == Data([0x01, 0x02, 0x03, 0x04]))
    }

    @Test func writesLittleEndianUInt64() {
        var writer = BinaryWriter()
        writer.writeUInt64(0x0807_0605_0403_0201)
        #expect(writer.data == Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]))
    }

    @Test func writesFloat32BitPattern() {
        var writer = BinaryWriter()
        writer.writeFloat32(1.5)
        var expected = Data()
        expected.appendFloat32(1.5)
        #expect(writer.data == expected)
    }

    @Test func writesRawBytes() {
        var writer = BinaryWriter()
        writer.write(Data([0x01, 0x02]))
        writer.write(Data([0x03]))
        #expect(writer.data == Data([0x01, 0x02, 0x03]))
        #expect(writer.count == 3)
    }

    @Test func writesZStringWithTerminator() throws {
        var writer = BinaryWriter()
        try writer.writeZString("abc")
        try writer.writeZString("def")
        #expect(writer.data == Data("abc\0def\0".utf8))
    }

    @Test func writeZStringWithEmbeddedNullThrows() {
        var writer = BinaryWriter()
        #expect(throws: BinaryWriterError.embeddedNull("a\0b")) {
            try writer.writeZString("a\0b")
        }
    }

    @Test func writeZStringUnencodableThrows() {
        var writer = BinaryWriter()
        // U+1F600 has no representation in windows-1252.
        let string = "\u{1F600}"
        #expect(throws: BinaryWriterError.unencodableString(string)) {
            try writer.writeZString(string)
        }
    }

    @Test func writesWindows1252() throws {
        var writer = BinaryWriter()
        try writer.writeZString("é")
        #expect(writer.data == Data([0xE9, 0x00]))
    }

    @Test func roundTripsThroughBinaryReader() throws {
        var writer = BinaryWriter()
        writer.writeUInt8(0x7F)
        writer.writeUInt16(0x1234)
        writer.writeUInt32(0xDEAD_BEEF)
        writer.writeUInt64(0x0123_4567_89AB_CDEF)
        writer.writeFloat32(-2.5)
        try writer.writeZString("hello")

        var reader = BinaryReader(writer.data)
        #expect(try reader.readUInt8() == 0x7F)
        #expect(try reader.readUInt16() == 0x1234)
        #expect(try reader.readUInt32() == 0xDEAD_BEEF)
        #expect(try reader.readUInt64() == 0x0123_4567_89AB_CDEF)
        #expect(try reader.readFloat32() == -2.5)
        #expect(try reader.readZString() == "hello")
        #expect(reader.bytesRemaining == 0)
    }
}
