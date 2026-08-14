// Synthetic load-order coverage for the M18 Asset Browser query and resolved
// inspector. No game records or extracted data are fixtures.

import Foundation
@testable import opensky
import Testing

struct ReferenceRecordCatalogTests {
    @Test
    func allNineTypesListByEditorIDAndNameTheWinningPlugin() throws {
        let base = try plugin(records: ReferenceRecordType.allCases.enumerated().map {
            record($0.element.rawValue, formID: UInt32($0.offset + 1), editorID: "Base\($0.offset)")
        })
        let patch = try plugin(
            masters: ["Base.esm"],
            records: [record("KYWD", formID: 1, editorID: "WinningKeyword")]
        )
        let index = RecordIndex(
            plugins: [("Base.esm", base), ("Patch.esp", patch)],
            recordTypes: RecordIndex.referenceRecordTypes
        )
        let catalog = ReferenceRecordCatalog(
            index: index,
            pluginNames: ["Base.esm", "Patch.esp"]
        )

        for type in ReferenceRecordType.allCases {
            #expect(catalog.items(for: type, winningPlugin: nil).count == 1)
        }
        #expect(
            catalog.items(for: .keyword, winningPlugin: nil).first?.display
                == "WinningKeyword — Patch.esp — Base.esm:000001"
        )
        #expect(catalog.items(for: .keyword, winningPlugin: "Base.esm").isEmpty)
        #expect(catalog.items(for: .keyword, winningPlugin: "Patch.esp").count == 1)
    }

    @Test
    func keywordInspectorListsUsersAndMarksDanglingFlattenedMembers() throws {
        let keyword = record("KYWD", formID: 1, editorID: "VendorKeyword")
        let item = record(
            "MISC",
            formID: 2,
            editorID: "TestItem",
            extraFields: ESMFixture.field("KWDA", words([1]))
        )
        let list = record(
            "FLST",
            formID: 3,
            editorID: "TestList",
            extraFields: ESMFixture.field("LNAM", words([0x99]))
        )
        let file = try plugin(records: [keyword, item, list])
        let index = RecordIndex(
            plugins: [("Base.esm", file)],
            recordTypes: RecordIndex.referenceRecordTypes
                .union(ReferenceRecordCatalog.inspectedItemTypes)
        )
        let inspector = ReferenceRecordInspector(index: index)
        let catalog = ReferenceRecordCatalog(index: index, pluginNames: ["Base.esm"])

        let keywordPreview = try previewRecord(in: catalog, type: .keyword)
        let keywordText = inspector.text(for: keywordPreview)
        #expect(keywordText.contains("winner plugin: Base.esm"))
        #expect(keywordText.contains("users (1):"))
        #expect(keywordText.contains("TestItem — Base.esm"))

        let listPreview = try previewRecord(in: catalog, type: .formList)
        let listText = inspector.text(for: listPreview)
        #expect(listText.contains("flattened membership"))
        #expect(listText.contains("[UNRESOLVED] Base.esm:000099"))
    }

    private func previewRecord(
        in catalog: ReferenceRecordCatalog,
        type: ReferenceRecordType
    ) throws -> PreviewRecord {
        let item = try #require(catalog.items(for: type, winningPlugin: nil).first)
        guard case let .record(preview) = item.selection else {
            throw ESMError.malformed("expected record preview")
        }
        return preview
    }

    private func plugin(masters: [String] = [], records: [Data]) throws -> ESMFile {
        let grouped = Dictionary(grouping: records) { data in
            String(bytes: data.prefix(4), encoding: .ascii) ?? "KYWD"
        }
        var bytes = ESMFixture.tes4(masters: masters)
        for (type, values) in grouped.sorted(by: { $0.key < $1.key }) {
            bytes += ESMFixture.topGroup(type, contents: values.reduce(Data(), +))
        }
        return try ESMFile(data: bytes)
    }

    private func record(
        _ type: String,
        formID: UInt32,
        editorID: String,
        extraFields: Data = Data()
    ) -> Data {
        ESMFixture.record(
            type,
            formID: formID,
            data: ESMFixture.field("EDID", ESMFixture.zstring(editorID)) + extraFields
        )
    }

    private func words(_ values: [UInt32]) -> Data {
        var data = Data()
        for value in values {
            data.appendUInt32(value)
        }
        return data
    }
}
