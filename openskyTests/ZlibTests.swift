// Zlib stream decoder tests. Streams are built by ESMFixture.zlibStream via
// Apple's Compression encoder + hand-computed RFC 1950 wrapper.

import Foundation
@testable import opensky
import Testing

struct ZlibTests {
    @Test func roundTripsCompressibleData() throws {
        let payload = Data(String(repeating: "meshes\\test.nif;", count: 100).utf8)
        let stream = ESMFixture.zlibStream(payload)
        #expect(stream.count < payload.count)
        let output = try Zlib.decompress(stream, decompressedSize: payload.count)
        #expect(output == payload)
    }

    @Test func zeroSizeSkipsDecoding() throws {
        let stream = ESMFixture.zlibStream(Data())
        #expect(try Zlib.decompress(stream, decompressedSize: 0) == Data())
    }

    @Test func rejectsBadHeader() {
        // 0x1234: method nibble is not 8 and the mod-31 check fails.
        #expect(throws: ZlibError.notZlib) {
            _ = try Zlib.decompress(Data([0x12, 0x34, 0x00]), decompressedSize: 1)
        }
        #expect(throws: ZlibError.notZlib) {
            _ = try Zlib.decompress(Data([0x78]), decompressedSize: 1)
        }
    }

    @Test func rejectsPresetDictionary() {
        // CMF 0x78, FLG with FDICT bit set; 0x78BB % 31 == 0.
        #expect(throws: ZlibError.presetDictionaryUnsupported) {
            _ = try Zlib.decompress(Data([0x78, 0xBB, 0x00]), decompressedSize: 1)
        }
    }

    @Test func rejectsWrongDeclaredSize() {
        let payload = Data("payload".utf8)
        let stream = ESMFixture.zlibStream(payload)
        #expect(throws: ZlibError.self) {
            _ = try Zlib.decompress(stream, decompressedSize: payload.count + 1)
        }
    }

    @Test func rejectsOversizedDeclaredSize() {
        #expect(throws: ZlibError.invalidSize(Zlib.sizeCap + 1)) {
            _ = try Zlib.decompress(Data([0x78, 0x9C]), decompressedSize: Zlib.sizeCap + 1)
        }
    }
}
