// Unit tests for the engine-wide game-data text decode policy: UTF-8 first,
// windows-1252 next, ISO 8859-1 last, and never a failure. Policy in
// docs/decisions/string-decoding.md.

import Foundation
@testable import opensky
import Testing

struct GameTextTests {
    @Test func prefersUTF8WhenTheBytesAreValidUTF8() {
        // "Brûlé" as UTF-8: the accented letters are two-byte sequences.
        let bytes = Data([0x42, 0x72, 0xC3, 0xBB, 0x6C, 0xC3, 0xA9])
        #expect(GameText.decode(bytes) == "Brûlé")
    }

    @Test func fallsBackToWindows1252() {
        // Same text as vanilla cp1252 bytes, which are not valid UTF-8.
        let bytes = Data([0x42, 0x72, 0xFB, 0x6C, 0xE9])
        #expect(GameText.decode(bytes) == "Brûlé")
        // 0x93/0x94 are curly quotes in cp1252 and unmapped in ISO 8859-1,
        // so this also proves cp1252 is tried before Latin-1.
        #expect(GameText.decode(Data([0x93, 0x61, 0x94])) == "\u{201C}a\u{201D}")
    }

    @Test func fallsBackToLatin1ForBytesWindows1252LeavesUndefined() {
        // 0x81, 0x8D, 0x8F, 0x90 and 0x9D have no cp1252 mapping. Vanilla NIF
        // string tables carry them as exporter junk.
        for byte in [UInt8(0x81), 0x8D, 0x8F, 0x90, 0x9D] {
            let text = GameText.decode(Data([byte, 0x61]))
            #expect(text == String(UnicodeScalar(byte)) + "a")
        }
    }

    @Test func decodesEveryByteSequenceRatherThanFailing() {
        // Lone surrogates, truncated UTF-8, raw binary: all decode to something.
        let cases = [Data([0xED, 0xA0, 0x80]), Data([0xC3]), Data((0 ... 255).map(UInt8.init))]
        for bytes in cases {
            #expect(!GameText.decode(bytes).isEmpty)
        }
        #expect(GameText.decode(Data()).isEmpty)
    }

    @Test func strictDecodingRejectsBytesOutsideItsEncoding() {
        #expect(TextDecoding.strict(.ascii).decode(Data([0xE9])) == nil)
        #expect(TextDecoding.strict(.ascii).decode(Data([0x61])) == "a")
        #expect(TextDecoding.gameText.decode(Data([0xE9])) == "é")
    }
}
