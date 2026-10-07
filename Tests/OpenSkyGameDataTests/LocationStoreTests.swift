// Synthetic load-order, parent-chain, keyword and CELL-link coverage.

@testable import FormatsTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

struct LocationStoreTests {
    @Test
    func parentContainmentAndInheritedKeywordQueriesTerminateAtCycles() throws {
        let file = try plugin(
            locations: [
                LocationFixture.recordBytes(0x10, "Hold", parent: 0x30, keywords: [0x40]),
                LocationFixture.recordBytes(0x20, "Dungeon", parent: 0x10),
                LocationFixture.recordBytes(0x30, "Cycle", parent: 0x20)
            ],
            keywords: [KeywordFixture.recordBytes(formID: 0x40, editorID: "LocTypeHold")]
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
    func uniqueActorsMapEachBaseToItsReference() throws {
        let file = try plugin(locations: [
            LocationFixture.recordBytes(
                0x10,
                "Town",
                uniqueActors: [0x50, 0x51, 0x10, 0x60, 0x61, 0x10]
            )
        ])
        let store = LocationStore(plugins: [("Base.esm", file)])

        #expect(store.uniqueActorReferences == [
            .plugin(name: "base.esm", objectID: 0x50): .plugin(name: "base.esm", objectID: 0x51),
            .plugin(name: "base.esm", objectID: 0x60): .plugin(name: "base.esm", objectID: 0x61)
        ])
    }

    @Test
    func laterPluginWinsByIdentityAndEditorID() throws {
        let base = try plugin(locations: [LocationFixture.recordBytes(0x10, "OldName")])
        let patch = try plugin(
            masters: ["Base.esm"],
            locations: [LocationFixture.recordBytes(0x10, "NewName")]
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
        let file = try plugin(locations: [LocationFixture.recordBytes(0x10, "InteriorLocation")])
        let store = LocationStore(plugins: [("Base.esm", file)])
        let cell = try cell(location: 0x10)

        #expect(cell.location == FormID(0x10))
        #expect(store.location(containing: cell, fromPlugin: "Base.esm")?.location.editorID
            == "InteriorLocation")
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

    private func cell(location: UInt32) throws -> Cell {
        let fields = ESMFixture.field("XLCN", ESMFixture.words([location]))
        let bytes = ESMFixture.record("CELL", formID: 0x50, data: fields)
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("cell fixture did not produce a record")
        }
        return try Cell(record: record, localized: false)
    }

    private func id(_ plugin: String, _ objectID: UInt32) -> ResolvedFormID {
        ResolvedFormID(plugin: plugin, objectID: objectID)
    }
}
