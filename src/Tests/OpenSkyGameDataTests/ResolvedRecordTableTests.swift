// The shared store build: load-order walk, skip counting, and lookups.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct ResolvedRecordTableTests {
    @Test
    func undecodableIdentityIsCountedWithItsFirstError() throws {
        let file = try KeywordFixture.plugin(keywords: [
            KeywordFixture.recordBytes(formID: 0x10, editorID: "Readable"),
            KeywordFixture.recordBytes(formID: 0x20, editorID: "Broken"),
            KeywordFixture.recordBytes(formID: 0x30, editorID: "Broken")
        ])
        let index = RecordIndex(plugins: [("Base.esm", file)], recordTypes: ["KYWD"])
        let table = ResolvedRecordTable(
            index: index,
            types: ["KYWD"],
            decode: Self.rejectingBroken,
            editorID: \.editorID,
            resolve: { id, keyword, _ in (id, keyword.editorID) }
        )

        #expect(table.values.count == 1)
        #expect(table.value(editorID: "READABLE")?.0.objectID == 0x10)
        #expect(table.skipped.count(of: "KYWD") == 2)
        #expect(table.skipped.total == 2)
        #expect(table.skipped.lines.count == 1)
        #expect(table.skipped.lines.first?.hasPrefix("KYWD: 2 skipped, first error:") == true)
        #expect(table.skipped.byType["KYWD"]?.firstError.contains("broken fixture") == true)
    }

    @Test
    func storeCountsAnEffectWithoutData() throws {
        let file = try ESMFile(
            data: ESMFixture.tes4()
                + ESMFixture.topGroup("MGEF", contents: ESMFixture.record(
                    "MGEF",
                    formID: 0x42,
                    data: ESMFixture.field("EDID", ESMFixture.zstring("NoData"))
                ))
        )
        let store = MagicEffectStore(plugins: [("Base.esm", file)])

        #expect(store.effects.isEmpty)
        #expect(store.skippedRecords.count(of: "MGEF") == 1)
        #expect(store.skippedRecords.byType["MGEF"]?.firstError.contains("DATA") == true)
    }

    @Test
    func overrideThatFallsBackToAnEarlierDefinitionIsNotASkip() throws {
        let base = try KeywordFixture.plugin(keywords: [KeywordFixture.recordBytes(
            formID: 0x42,
            editorID: "BaseKeyword"
        )])
        let patch = try KeywordFixture.plugin(
            masters: ["Base.esm"],
            keywords: [KeywordFixture.recordBytes(formID: 0x42, editorID: "Broken")]
        )
        let index = RecordIndex(
            plugins: [("Base.esm", base), ("Patch.esp", patch)],
            recordTypes: ["KYWD"]
        )
        let table = ResolvedRecordTable(
            index: index,
            types: ["KYWD"],
            decode: Self.rejectingBroken,
            editorID: \.editorID,
            resolve: { _, keyword, sourcePlugin in (keyword.editorID, sourcePlugin) }
        )

        #expect(table.value(editorID: "BaseKeyword")?.1 == "Base.esm")
        #expect(table.skipped.isEmpty)
    }

    @Test
    func lookupFallsBackToACaseInsensitivePluginName() throws {
        let file = try KeywordFixture.plugin(keywords: [KeywordFixture.recordBytes(
            formID: 0x10,
            editorID: "Readable"
        )])
        let store = KeywordStore(plugins: [("Base.esm", file)])

        #expect(store.keyword(ResolvedFormID(plugin: "BASE.ESM", objectID: 0x10)) != nil)
    }

    @Test
    func lookupMissesAnUnknownObjectOrPlugin() throws {
        let file = try KeywordFixture.plugin(keywords: [KeywordFixture.recordBytes(
            formID: 0x10,
            editorID: "Readable"
        )])
        let store = KeywordStore(plugins: [("Base.esm", file)])

        #expect(store.keyword(ResolvedFormID(plugin: "base.esm", objectID: 0x11)) == nil)
        #expect(store.keyword(ResolvedFormID(plugin: "Other.esm", objectID: 0x10)) == nil)
    }

    @Test
    func mergeKeepsTheFirstErrorAndAddsCounts() {
        var left = SkippedRecords()
        left.note("KYWD", error: ESMError.malformed("left"))
        var right = SkippedRecords()
        right.note("KYWD", error: ESMError.malformed("right"))
        right.note("FLST", error: ESMError.malformed("list"))

        let merged = left.merging(right)

        #expect(merged.count(of: "KYWD") == 2)
        #expect(merged.byType["KYWD"]?.firstError.contains("left") == true)
        #expect(merged.count(of: "FLST") == 1)
        #expect(merged.total == 3)
    }

    private static func rejectingBroken(_ indexed: IndexedRecord) throws -> Keyword {
        let keyword = try Keyword(record: indexed.record)
        guard keyword.editorID != "Broken" else {
            throw ESMError.malformed("broken fixture keyword")
        }
        return keyword
    }
}
