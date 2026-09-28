// TranslationFile parser tests over synthetic in-code fixtures
// (TranslationFileFixture). Covers BOM/no-BOM, CRLF/LF, missing tab, empty
// value, duplicate keys, case-sensitive keys, non-ASCII values, big-endian
// tolerance, and malformed (truncated) input.

import Foundation
@testable import opensky
import Testing

struct TranslationFileTests {
    @Test func parsesKeyValuePairsWithBOMandCRLF() throws {
        let data = TranslationFileFixture.file([
            (key: "$ExitGame", value: "Quit"),
            (key: "$Continue", value: "Continue")
        ])
        let file = try TranslationFile(data: data)
        #expect(file.count == 2)
        #expect(file.value(forKey: "$ExitGame") == "Quit")
        #expect(file.value(forKey: "$Continue") == "Continue")
        #expect(file.value(forKey: "$Missing") == nil)
    }

    @Test func parsesWithoutBOM() throws {
        let data = TranslationFileFixture.file([(key: "$A", value: "one")], bom: false)
        #expect(try TranslationFile(data: data).value(forKey: "$A") == "one")
    }

    @Test func parsesLFLineEndings() throws {
        let data = TranslationFileFixture.file(
            [(key: "$A", value: "one"), (key: "$B", value: "two")],
            lineEnding: "\n"
        )
        let file = try TranslationFile(data: data)
        #expect(file.value(forKey: "$A") == "one")
        #expect(file.value(forKey: "$B") == "two")
    }

    @Test func skipsLinesWithoutATab() throws {
        // A stray line with no tab must not reject the whole file.
        let text = "$A\tone\r\nnot a pair line\r\n$B\ttwo\r\n"
        let file = try TranslationFile(data: TranslationFileFixture.encode(text))
        #expect(file.count == 2)
        #expect(file.value(forKey: "$A") == "one")
        #expect(file.value(forKey: "$B") == "two")
    }

    @Test func keepsEmptyValue() throws {
        let data = TranslationFileFixture.file([(key: "$Empty", value: "")])
        #expect(try TranslationFile(data: data).value(forKey: "$Empty")?.isEmpty == true)
    }

    @Test func duplicateKeyLastWins() throws {
        let data = TranslationFileFixture.file([
            (key: "$K", value: "first"),
            (key: "$K", value: "second")
        ])
        let file = try TranslationFile(data: data)
        #expect(file.count == 1)
        #expect(file.value(forKey: "$K") == "second")
    }

    @Test func keysAreCaseSensitive() throws {
        let data = TranslationFileFixture.file([
            (key: "$Key", value: "upper"),
            (key: "$key", value: "lower")
        ])
        let file = try TranslationFile(data: data)
        #expect(file.count == 2)
        #expect(file.value(forKey: "$Key") == "upper")
        #expect(file.value(forKey: "$key") == "lower")
    }

    @Test func decodesNonASCIIValues() throws {
        let data = TranslationFileFixture.file([
            (key: "$Cafe", value: "Café"),
            (key: "$City", value: "Vædстрið 🗡"),
            (key: "$Umlaut", value: "Grüße")
        ])
        let file = try TranslationFile(data: data)
        #expect(file.value(forKey: "$Cafe") == "Café")
        #expect(file.value(forKey: "$City") == "Vædстрið 🗡")
        #expect(file.value(forKey: "$Umlaut") == "Grüße")
    }

    @Test func valueKeepsEmbeddedTabs() throws {
        // Only the first tab splits key from value; the rest belong to value.
        let file = try TranslationFile(data: TranslationFileFixture.encode("$K\ta\tb\r\n"))
        #expect(file.value(forKey: "$K") == "a\tb")
    }

    @Test func toleratesBigEndianBOM() throws {
        let data = TranslationFileFixture.file([(key: "$A", value: "one")], bigEndian: true)
        #expect(try TranslationFile(data: data).value(forKey: "$A") == "one")
    }

    @Test func emptyFileYieldsEmptyTable() throws {
        let file = try TranslationFile(data: TranslationFileFixture.encode(""))
        #expect(file.isEmpty)
        #expect(file.value(forKey: "$A") == nil)
    }

    @Test func toleratesTruncatedTrailingByte() throws {
        // An odd trailing byte (half a code unit) is dropped by the decoder;
        // the valid prefix still parses rather than crashing.
        var data = TranslationFileFixture.file([(key: "$A", value: "one")])
        data.append(0x41)
        #expect(try TranslationFile(data: data).value(forKey: "$A") == "one")
    }

    @Test func rejectsUndecodableUTF16() {
        // A lone high surrogate is not valid UTF-16 and must be rejected.
        var data = TranslationFileFixture.file([(key: "$A", value: "one")])
        data.append(contentsOf: [0x00, 0xD8])
        #expect(throws: TranslationFileError.notUTF16) {
            _ = try TranslationFile(data: data)
        }
    }
}
