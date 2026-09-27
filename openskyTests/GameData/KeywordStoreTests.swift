// Cross-plugin KYWD lookup and KWDA resolution over synthetic ESM fixtures.

import Foundation
@testable import opensky
import Testing

struct KeywordStoreTests {
    @Test
    func laterOverrideWinsAndEditorIDLookupIsCaseInsensitive() throws {
        let base = try plugin(keywords: [
            keyword(formID: 0x42, editorID: "VendorItemWeapon")
        ])
        let patch = try plugin(
            masters: ["Base.esm"],
            keywords: [keyword(formID: 0x42, editorID: "PatchedVendorKeyword")]
        )
        let store = KeywordStore(plugins: [("Base.esm", base), ("Patch.esp", patch)])

        let resolved = try #require(
            store.keyword(ResolvedFormID(plugin: "Base.esm", objectID: 0x42))
        )
        #expect(resolved.keyword.editorID == "PatchedVendorKeyword")
        #expect(resolved.sourcePlugin == "Patch.esp")
        #expect(store.keyword(editorID: "patchedvendorkeyword")?.id == resolved.id)
        #expect(store.keyword(editorID: "VENDORITEMWEAPON") == nil)
    }

    @Test
    func laterPluginWinsWhenDifferentIdentitiesShareAnEditorID() throws {
        let base = try plugin(keywords: [
            keyword(formID: 0x10, editorID: "SharedKeyword")
        ])
        let patch = try plugin(keywords: [
            keyword(formID: 0x20, editorID: "SharedKeyword")
        ])
        let store = KeywordStore(plugins: [("Base.esm", base), ("Patch.esp", patch)])

        #expect(
            store.keyword(editorID: "sharedkeyword")?.id
                == ResolvedFormID(plugin: "Patch.esp", objectID: 0x20)
        )
    }

    @Test
    func keywordListResolvesTwoPluginLinksAndTestsByName() throws {
        let base = try plugin(keywords: [
            keyword(formID: 1, editorID: "VendorItemWeapon"),
            keyword(formID: 2, editorID: "WeapTypeSword")
        ])
        let child = try plugin(
            masters: ["Base.esm"],
            keywords: [keyword(formID: 0x0100_0003, editorID: "PatchOnlyKeyword")]
        )
        let store = KeywordStore(plugins: [("Base.esm", base), ("Patch.esp", child)])
        var list = KeywordList()
        var payload = Data()
        payload.appendUInt32(1)
        payload.appendUInt32(0x0100_0003)
        let consumed = try list.decode(field: ESMField(type: "KWDA", data: payload))
        #expect(consumed)

        #expect(
            list.displayStrings(fromPlugin: "Patch.esp", using: store)
                == ["VendorItemWeapon", "PatchOnlyKeyword"]
        )
        #expect(list.contains(editorID: "vendoritemweapon", fromPlugin: "Patch.esp", using: store))
        #expect(list.contains(editorID: "PATCHONLYKEYWORD", fromPlugin: "Patch.esp", using: store))
        #expect(!list.contains(editorID: "WeapTypeSword", fromPlugin: "Patch.esp", using: store))
    }

    @Test
    func danglingKeywordRemainsVisibleInDisplayText() throws {
        let file = try plugin(keywords: [])
        let store = KeywordStore(plugins: [("Base.esm", file)])

        #expect(
            store.displayString(for: FormID(0x00AB_CDEF), fromPlugin: "Base.esm")
                == "[UNRESOLVED] 00ABCDEF"
        )
    }

    @Test
    func recordDumpPrintsReferenceRecordsAndResolvedItemKeywords() throws {
        let keywords = try plugin(keywords: [
            keyword(formID: 1, editorID: "VendorItemWeapon")
        ])
        let store = KeywordStore(plugins: [("Base.esm", keywords)])
        let keywordRecord = try firstRecord(in: keywords, type: "KYWD")
        let itemRecord = try firstRecord(
            type: "MISC",
            fields: ESMFixture.field("EDID", ESMFixture.zstring("TestItem"))
                + InventoryFixture.keywordFields([1])
        )

        let keywordDump = RecordTextDump.dump(record: keywordRecord, localized: false)
        let itemDump = RecordTextDump.dump(
            record: itemRecord,
            localized: false,
            keywordStore: store,
            sourcePlugin: "Base.esm"
        )

        #expect(keywordDump.contains("decoded KYWD: editorID VendorItemWeapon"))
        #expect(itemDump.contains("keywords [VendorItemWeapon]"))
        #expect(!itemDump.contains("keywords [00000001]"))
    }

    private func plugin(masters: [String] = [], keywords: [Data]) throws -> ESMFile {
        try ESMFile(
            data: ESMFixture.tes4(masters: masters)
                + ESMFixture.topGroup("KYWD", contents: keywords.reduce(Data(), +))
        )
    }

    private func keyword(formID: UInt32, editorID: String) -> Data {
        ESMFixture.record(
            "KYWD",
            formID: formID,
            data: ESMFixture.field("EDID", ESMFixture.zstring(editorID))
                + ESMFixture.field("CNAM", Data([1, 2, 3, 4]))
        )
    }

    private func firstRecord(type: String, fields: Data) throws -> ESMRecord {
        let file = try ESMFile(
            data: ESMFixture.tes4()
                + ESMFixture.topGroup(
                    type,
                    contents: ESMFixture.record(type, formID: 0x100, data: fields)
                )
        )
        return try firstRecord(in: file, type: type)
    }

    private func firstRecord(in file: ESMFile, type: String) throws -> ESMRecord {
        let group = try #require(file.topGroups.first { $0.recordType?.description == type })
        let child = try #require(try group.children().first)
        guard case let .record(record) = child else {
            throw ESMError.malformed("fixture child is not a record")
        }
        return record
    }
}
