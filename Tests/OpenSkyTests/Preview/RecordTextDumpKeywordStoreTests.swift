// Record dumps that name linked records through `KeywordStore`. In-code plugin fixtures only.

import FormatsTestSupport
import Foundation
@testable import OpenSkyEngine
@testable import OpenSkyFormats
@testable import OpenSkyGameData
import Testing

struct RecordTextDumpKeywordStoreTests {
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
