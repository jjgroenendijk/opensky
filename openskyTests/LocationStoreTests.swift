// Synthetic load-order, parent-chain, keyword and CELL-link coverage.

import Foundation
@testable import opensky
import Testing

struct LocationStoreTests {
    @Test
    func parentContainmentAndInheritedKeywordQueriesTerminateAtCycles() throws {
        let file = try plugin(
            locations: [
                location(0x10, "Hold", parent: 0x30, keywords: [0x40]),
                location(0x20, "Dungeon", parent: 0x10),
                location(0x30, "Cycle", parent: 0x20)
            ],
            keywords: [keyword(0x40, "LocTypeHold")]
        )
        let store = LocationStore(plugins: [("Base.esm", file)])
        let dungeon = id("Base.esm", 0x20)

        #expect(store.isWithin(dungeon, ancestor: id("Base.esm", 0x10)))
        #expect(store.isWithin(dungeon, ancestor: dungeon))
        #expect(!store.isWithin(dungeon, ancestor: id("Base.esm", 0x99)))
        #expect(store.hasKeyword(editorID: "loctypehold", in: dungeon))
        #expect(!store.hasKeyword(editorID: "Missing", in: dungeon))
    }

    @Test
    func laterPluginWinsByIdentityAndEditorID() throws {
        let base = try plugin(locations: [location(0x10, "OldName")])
        let patch = try plugin(
            masters: ["Base.esm"],
            locations: [location(0x10, "NewName")]
        )
        let store = LocationStore(plugins: [("Base.esm", base), ("Patch.esp", patch)])

        let resolved = try #require(store.location(id("Base.esm", 0x10)))
        #expect(resolved.location.editorID == "NewName")
        #expect(resolved.sourcePlugin == "Patch.esp")
        #expect(store.location(editorID: "newname")?.id == resolved.id)
        #expect(store.location(editorID: "OLDNAME") == nil)
    }

    @Test
    func cellLocationLinkResolvesThroughTheStore() throws {
        let file = try plugin(locations: [location(0x10, "InteriorLocation")])
        let store = LocationStore(plugins: [("Base.esm", file)])
        let cell = try cell(location: 0x10)

        #expect(cell.location == FormID(0x10))
        #expect(store.location(containing: cell, fromPlugin: "Base.esm")?.location.editorID
            == "InteriorLocation")
    }

    @Test
    func recordDumpNamesResolvedLocationKeywords() throws {
        let file = try plugin(
            locations: [location(0x10, "DumpLocation", parent: 0x11, keywords: [0x40])],
            keywords: [keyword(0x40, "LocTypeDungeon")]
        )
        let index = RecordIndex(
            plugins: [("Base.esm", file)],
            recordTypes: RecordIndex.referenceRecordTypes
        )
        let record = try #require(index.records[id("Base.esm", 0x10)]?.record)
        let dump = RecordTextDump.dump(
            record: record,
            localized: false,
            keywordStore: KeywordStore(index: index),
            formListStore: FormListStore(index: index),
            sourcePlugin: "Base.esm"
        )

        #expect(dump.contains("decoded LCTN: editorID DumpLocation"))
        #expect(dump.contains("parent 00000011"))
        #expect(dump.contains("keywords [LocTypeDungeon]"))
    }

    private func plugin(
        masters: [String] = [],
        locations: [Data],
        keywords: [Data] = []
    ) throws -> ESMFile {
        var data = ESMFixture.tes4(masters: masters)
        if !locations.isEmpty {
            data += ESMFixture.topGroup("LCTN", contents: locations.reduce(Data(), +))
        }
        if !keywords.isEmpty {
            data += ESMFixture.topGroup("KYWD", contents: keywords.reduce(Data(), +))
        }
        return try ESMFile(data: data)
    }

    private func location(
        _ formID: UInt32,
        _ editorID: String,
        parent: UInt32? = nil,
        keywords: [UInt32] = []
    ) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        if let parent {
            fields += ESMFixture.field("PNAM", words([parent]))
        }
        if !keywords.isEmpty {
            fields += ESMFixture.field("KSIZ", words([UInt32(keywords.count)]))
                + ESMFixture.field("KWDA", words(keywords))
        }
        return ESMFixture.record("LCTN", formID: formID, data: fields)
    }

    private func keyword(_ formID: UInt32, _ editorID: String) -> Data {
        ESMFixture.record(
            "KYWD",
            formID: formID,
            data: ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        )
    }

    private func cell(location: UInt32) throws -> Cell {
        let fields = ESMFixture.field("XLCN", words([location]))
        let bytes = ESMFixture.record("CELL", formID: 0x50, data: fields)
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("cell fixture did not produce a record")
        }
        return try Cell(record: record, localized: false)
    }

    private func words(_ values: [UInt32]) -> Data {
        var data = Data()
        for value in values {
            data.appendUInt32(value)
        }
        return data
    }

    private func id(_ plugin: String, _ objectID: UInt32) -> ResolvedFormID {
        ResolvedFormID(plugin: plugin, objectID: objectID)
    }
}
