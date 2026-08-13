// Cross-plugin FLST indexing, flattening and membership over synthetic ESMs.

import Foundation
@testable import opensky
import Testing

struct FormListStoreTests {
    @Test
    func nestedListsFlattenInOrderAndMembershipUsesLeaves() throws {
        let file = try plugin(formLists: [
            list(0x10, "Inner", [1, 2]),
            list(0x20, "Outer", [3, 0x10, 4])
        ])
        let store = FormListStore(plugins: [("Base.esm", file)])
        let outer = id("Base.esm", 0x20)

        let flattened = try #require(store.flattened(outer))

        #expect(flattened.entries == [
            id("Base.esm", 3),
            id("Base.esm", 1),
            id("Base.esm", 2),
            id("Base.esm", 4)
        ])
        #expect(flattened.maximumDepth == 1)
        #expect(!flattened.hitDepthCap)
        #expect(store.contains(id("Base.esm", 2), in: outer))
        #expect(!store.contains(id("Base.esm", 0x10), in: outer))
    }

    @Test
    func selfReferenceTerminatesWithoutDroppingOtherEntries() throws {
        let file = try plugin(formLists: [list(0x10, "Self", [1, 0x10, 2])])
        let store = FormListStore(plugins: [("Base.esm", file)])

        #expect(
            store.flattened(id("Base.esm", 0x10))?.entries
                == [id("Base.esm", 1), id("Base.esm", 2)]
        )
    }

    @Test
    func twoListCycleTerminatesWithoutSuppressingRepeatedAcyclicExpansion() throws {
        let file = try plugin(formLists: [
            list(0x10, "First", [1, 0x20]),
            list(0x20, "Second", [2, 0x10]),
            list(0x30, "Repeated", [0x10, 0x10])
        ])
        let store = FormListStore(plugins: [("Base.esm", file)])

        #expect(
            store.flattened(id("Base.esm", 0x10))?.entries
                == [id("Base.esm", 1), id("Base.esm", 2)]
        )
        #expect(
            store.flattened(id("Base.esm", 0x30))?.entries
                == [id("Base.esm", 1), id("Base.esm", 2), id("Base.esm", 1), id("Base.esm", 2)]
        )
    }

    @Test
    func laterOverrideReplacesTheWholeList() throws {
        let base = try plugin(formLists: [list(0x10, "BaseList", [1, 2])])
        let patch = try plugin(
            masters: ["Base.esm"],
            formLists: [list(0x10, "PatchedList", [3])]
        )
        let store = FormListStore(plugins: [("Base.esm", base), ("Patch.esp", patch)])

        let resolved = try #require(store.formList(id("Base.esm", 0x10)))
        #expect(resolved.list.entries == [FormID(3)])
        #expect(resolved.sourcePlugin == "Patch.esp")
        #expect(store.formList(editorID: "patchedlist")?.id == resolved.id)
        #expect(store.formList(editorID: "BASELIST") == nil)
    }

    @Test
    func nestedListResolvesLeavesRelativeToItsOwnPlugin() throws {
        let base = try plugin(formLists: [list(0x10, "BaseInner", [1])])
        let patch = try plugin(
            masters: ["Base.esm"],
            formLists: [list(0x0100_0020, "PatchOuter", [0x10, 0x0100_0002])]
        )
        let store = FormListStore(plugins: [("Base.esm", base), ("Patch.esp", patch)])

        #expect(
            store.flattened(id("Patch.esp", 0x20))?.entries
                == [id("Base.esm", 1), id("Patch.esp", 2)]
        )
    }

    @Test
    func nullEntrySurvivesFlatteningAtItsOriginalPosition() throws {
        let file = try plugin(formLists: [list(0x10, "WithNull", [1, 0, 2])])
        let store = FormListStore(plugins: [("Base.esm", file)])

        #expect(
            store.flattened(id("Base.esm", 0x10))?.entries
                == [id("Base.esm", 1), nil, id("Base.esm", 2)]
        )
    }

    @Test
    func acyclicHostileListStopsAtTheDepthCap() throws {
        let lists = (0 ... FormListStore.depthCap + 1).map { index in
            let objectID = UInt32(0x100 + index)
            let entries = index <= FormListStore.depthCap
                ? [UInt32(0x101 + index)]
                : [UInt32(1)]
            return list(objectID, "Depth\(index)", entries)
        }
        let file = try plugin(formLists: lists)
        let store = FormListStore(plugins: [("Base.esm", file)])

        let flattened = try #require(store.flattened(id("Base.esm", 0x100)))
        #expect(flattened.entries.isEmpty)
        #expect(flattened.maximumDepth == FormListStore.depthCap)
        #expect(flattened.hitDepthCap)
    }

    @Test
    func recordDumpCapsEntriesAndNamesDecodedReferenceTargets() throws {
        var entries = [UInt32](repeating: 1, count: RecordTextDump.fieldPrintCap + 1)
        entries[1] = 0
        let lists = try plugin(
            formLists: [list(0x10, "DumpList", entries)],
            keywords: [keyword(1, "NamedKeyword")]
        )
        let index = RecordIndex(
            plugins: [("Base.esm", lists)],
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

        #expect(dump.contains("decoded FLST: editorID DumpList, entries 65"))
        #expect(dump.contains("NamedKeyword, NULL"))
        #expect(dump.contains("... 1 more"))
    }

    private func plugin(
        masters: [String] = [],
        formLists: [Data],
        keywords: [Data] = []
    ) throws -> ESMFile {
        var data = ESMFixture.tes4(masters: masters)
        if !formLists.isEmpty {
            data += ESMFixture.topGroup("FLST", contents: formLists.reduce(Data(), +))
        }
        if !keywords.isEmpty {
            data += ESMFixture.topGroup("KYWD", contents: keywords.reduce(Data(), +))
        }
        return try ESMFile(data: data)
    }

    private func list(_ formID: UInt32, _ editorID: String, _ entries: [UInt32]) -> Data {
        FormListTests.recordBytes(formID: formID, editorID: editorID, entries: entries)
    }

    private func keyword(_ formID: UInt32, _ editorID: String) -> Data {
        ESMFixture.record(
            "KYWD",
            formID: formID,
            data: ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        )
    }

    private func id(_ plugin: String, _ objectID: UInt32) -> ResolvedFormID {
        ResolvedFormID(plugin: plugin, objectID: objectID)
    }
}
