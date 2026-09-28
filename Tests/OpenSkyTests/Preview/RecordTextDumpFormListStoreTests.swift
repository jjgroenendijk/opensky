// Record dumps that name linked records through `FormListStore`. In-code plugin fixtures only.

import FormatsTestSupport
import Foundation
@testable import OpenSkyEngine
@testable import OpenSkyFormats
@testable import OpenSkyGameData
import Testing

struct RecordTextDumpFormListStoreTests {
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
        FormListFixture.recordBytes(formID: formID, editorID: editorID, entries: entries)
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
