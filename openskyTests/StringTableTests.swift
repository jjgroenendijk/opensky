// String table parser tests over synthetic in-code fixtures
// (StringTableFixture). Covers all three entry framings, the lenient
// UTF-8 -> windows-1252 decode policy, and malformed-input rejection.

import Foundation
@testable import opensky
import Testing

struct StringTableTests {
    @Test func readsZStringEntries() throws {
        let data = StringTableFixture.table(
            kind: .strings,
            entries: [(7, "Iron Sword"), (0x0001_2E49, "Whiterun"), (9, "")]
        )
        let table = try StringTable(data: data, kind: .strings)
        #expect(table.count == 3)
        #expect(try table.string(id: 7) == "Iron Sword")
        #expect(try table.string(id: 0x0001_2E49) == "Whiterun")
        #expect(try table.string(id: 9)?.isEmpty == true)
        #expect(try table.string(id: 8) == nil)
    }

    @Test(arguments: [StringTable.Kind.dlstrings, .ilstrings])
    func readsLengthPrefixedEntries(kind: StringTable.Kind) throws {
        let data = StringTableFixture.table(
            kind: kind,
            entries: [(1, "A long book text."), (2, "")]
        )
        let table = try StringTable(data: data, kind: kind)
        #expect(try table.string(id: 1) == "A long book text.")
        #expect(try table.string(id: 2)?.isEmpty == true)
    }

    @Test func readsEmptyTable() throws {
        let table = try StringTable(
            data: StringTableFixture.table(kind: .strings, entries: []),
            kind: .strings
        )
        #expect(table.isEmpty)
        #expect(try table.string(id: 1) == nil)
    }

    @Test func decodesUTF8() throws {
        let data = StringTableFixture.table(kind: .strings, entries: [(1, "Café Sørine")])
        #expect(try StringTable(data: data, kind: .strings).string(id: 1) == "Café Sørine")
    }

    @Test func fallsBackToWindows1252() throws {
        // 0xE9 alone is invalid UTF-8 but "é" in windows-1252.
        let data = StringTableFixture.table(
            kind: .strings,
            rawEntries: [(1, Data([0x43, 0x61, 0x66, 0xE9]))]
        )
        #expect(try StringTable(data: data, kind: .strings).string(id: 1) == "Café")
    }

    @Test func duplicateIDKeepsFirst() throws {
        let data = StringTableFixture.table(
            kind: .strings,
            entries: [(1, "first"), (1, "second")]
        )
        let table = try StringTable(data: data, kind: .strings)
        #expect(table.count == 1)
        #expect(try table.string(id: 1) == "first")
    }

    @Test func kindFromFileExtension() {
        #expect(StringTable.Kind(fileExtension: "STRINGS") == .strings)
        #expect(StringTable.Kind(fileExtension: "DLStrings") == .dlstrings)
        #expect(StringTable.Kind(fileExtension: "ilstrings") == .ilstrings)
        #expect(StringTable.Kind(fileExtension: "esm") == nil)
    }

    @Test func rejectsTruncatedHeader() {
        #expect(throws: StringTableError.self) {
            _ = try StringTable(data: Data([1, 0, 0]), kind: .strings)
        }
    }

    @Test func rejectsTruncatedDataBlock() {
        var data = StringTableFixture.table(kind: .strings, entries: [(1, "Iron Sword")])
        data = data.dropLast(4)
        #expect(throws: StringTableError.self) {
            _ = try StringTable(data: data, kind: .strings)
        }
    }

    @Test func rejectsDirectoryOffsetPastDataBlock() {
        var data = Data()
        data.appendUInt32(1) // one entry
        data.appendUInt32(2) // 2-byte data block
        data.appendUInt32(1) // id
        data.appendUInt32(9) // offset beyond dataSize
        data.append(contentsOf: [0x41, 0x00])
        #expect(throws: StringTableError.entryOutOfRange(id: 1)) {
            _ = try StringTable(data: data, kind: .strings)
        }
    }

    @Test func throwsOnUnterminatedZString() throws {
        var data = Data()
        data.appendUInt32(1)
        data.appendUInt32(2) // data block: "AB", no terminator
        data.appendUInt32(5)
        data.appendUInt32(0)
        data.append(contentsOf: [0x41, 0x42])
        let table = try StringTable(data: data, kind: .strings)
        #expect(throws: StringTableError.entryOutOfRange(id: 5)) {
            _ = try table.string(id: 5)
        }
    }

    @Test func throwsWhenLengthPrefixOverrunsBlock() throws {
        var data = Data()
        data.appendUInt32(1)
        data.appendUInt32(6) // block: length prefix claims 99 bytes, only 2 follow
        data.appendUInt32(3)
        data.appendUInt32(0)
        data.appendUInt32(99)
        data.append(contentsOf: [0x41, 0x00])
        let table = try StringTable(data: data, kind: .dlstrings)
        #expect(throws: StringTableError.entryOutOfRange(id: 3)) {
            _ = try table.string(id: 3)
        }
    }

    @Test func toleratesTrailingGarbageAfterDataBlock() throws {
        let data = StringTableFixture.table(kind: .strings, entries: [(1, "ok")])
            + Data([0xDE, 0xAD])
        #expect(try StringTable(data: data, kind: .strings).string(id: 1) == "ok")
    }
}
