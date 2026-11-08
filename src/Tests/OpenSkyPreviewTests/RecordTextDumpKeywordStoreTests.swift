// Record dumps that name linked records through `KeywordStore`. In-code plugin fixtures only.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyPreview
import Testing

struct RecordTextDumpKeywordStoreTests {
    @Test
    func recordDumpPrintsReferenceRecordsAndResolvedItemKeywords() throws {
        let keywords = try KeywordFixture.plugin(keywords: [
            KeywordFixture.recordBytes(formID: 1, editorID: "VendorItemWeapon", hasColor: true)
        ])
        let store = KeywordStore(plugins: [("Base.esm", keywords)])
        let keywordRecord = try ESMFixture.firstRecord(type: "KYWD", in: keywords)
        let itemRecord = try ESMFixture.parsedRecord(
            type: "MISC",
            fields: ESMFixture.field("EDID", ESMFixture.zstring("TestItem"))
                + InventoryFixture.keywordFields([1]),
            formID: 0x100
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
}
