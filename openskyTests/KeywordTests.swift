// Synthetic KYWD/AACT decoder coverage. No game-derived bytes.

import Foundation
@testable import opensky
import Testing

struct KeywordTests {
    @Test
    func decodesKeywordEditorIDAndColor() throws {
        let record = try fixtureRecord(
            type: "KYWD",
            fields: ESMFixture.field("EDID", ESMFixture.zstring("VendorItemWeapon"))
                + ESMFixture.field("CNAM", Data([10, 20, 30, 40]))
        )

        let keyword = try Keyword(record: record)

        #expect(keyword.formID == FormID(0x123))
        #expect(keyword.editorID == "VendorItemWeapon")
        #expect(
            keyword.editorColor
                == ReferenceRecordColor(red: 10, green: 20, blue: 30, alpha: 40)
        )
        #expect(keyword.skipped.total == 0)
    }

    @Test
    func decodesActionAndAllowsEmptyVanillaVariant() throws {
        let populated = try ActionRecord(
            record: fixtureRecord(
                type: "AACT",
                fields: ESMFixture.field("EDID", ESMFixture.zstring("ActionActivate"))
                    + ESMFixture.field("CNAM", Data([1, 2, 3, 4]))
            )
        )
        let empty = try ActionRecord(record: fixtureRecord(type: "AACT", fields: Data()))

        #expect(populated.editorID == "ActionActivate")
        #expect(populated.editorColor?.alpha == 4)
        #expect(empty.editorID == nil)
        #expect(empty.editorColor == nil)
    }

    @Test
    func wrongRecordTypesThrow() throws {
        let action = try fixtureRecord(type: "AACT", fields: Data())
        let keyword = try fixtureRecord(type: "KYWD", fields: Data())

        #expect(throws: ESMError.self) {
            _ = try Keyword(record: action)
        }
        #expect(throws: ESMError.self) {
            _ = try ActionRecord(record: keyword)
        }
    }

    @Test
    func malformedAndUnknownFieldsAreTalliedWithoutDroppingRecord() throws {
        let fields = ESMFixture.field("EDID", Data("unterminated".utf8))
            + ESMFixture.field("CNAM", Data([1, 2, 3]))
            + ESMFixture.field("FULL", ESMFixture.zstring("ignored"))
        let keyword = try Keyword(record: fixtureRecord(type: "KYWD", fields: fields))

        #expect(keyword.editorID == nil)
        #expect(keyword.editorColor == nil)
        #expect(keyword.skipped.counts[.malformedField("EDID")] == 1)
        #expect(keyword.skipped.counts[.malformedField("CNAM")] == 1)
        #expect(keyword.skipped.counts[.unknownField("FULL")] == 1)
    }

    private func fixtureRecord(type: String, fields: Data) throws -> ESMRecord {
        let plugin = ESMFixture.tes4()
            + ESMFixture.topGroup(
                type,
                contents: ESMFixture.record(type, formID: 0x123, data: fields)
            )
        let file = try ESMFile(data: plugin)
        let group = try #require(file.topGroups.first { $0.recordType?.description == type })
        let child = try #require(try group.children().first)
        guard case let .record(record) = child else {
            throw ESMError.malformed("fixture child is not a record")
        }
        return record
    }
}
