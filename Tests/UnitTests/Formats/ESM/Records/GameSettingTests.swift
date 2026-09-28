// Synthetic GMST records only. Layout and type selection follow the open xEdit
// definitions cited by GameSetting; no game data is copied into fixtures.

import Foundation
@testable import opensky
import Testing

struct GameSettingTests {
    @Test
    func decodesFloatIntegerBooleanAndInlineString() throws {
        #expect(try setting("fSpeed", data: scalar(Float(12.5).bitPattern)).value == .float(12.5))
        #expect(try setting("iCount", data: scalar(UInt32.max)).value == .integer(-1))
        #expect(try setting("bEnabled", data: scalar(1)).value == .boolean(true))
        #expect(
            try setting("sLabel", data: ESMFixture.zstring("Walk")).value
                == .string(.inline("Walk"))
        )
    }

    @Test
    func decodesLocalizedStringTableID() throws {
        let decoded = try setting("sLabel", data: scalar(0x1234), localized: true)
        #expect(decoded.value == .string(.tableID(0x1234)))
    }

    @Test
    func rejectsWrongSizesUnknownPrefixesAndInvalidBoolean() throws {
        #expect(throws: GameSettingError.invalidDataSize(
            editorID: "fSpeed", expected: 4, actual: 3
        )) {
            try setting("fSpeed", data: Data([0, 0, 0]))
        }
        #expect(throws: GameSettingError.unsupportedPrefix("x")) {
            try setting("xMystery", data: scalar(0))
        }
        #expect(throws: GameSettingError.invalidBoolean(editorID: "bEnabled", rawValue: 2)) {
            try setting("bEnabled", data: scalar(2))
        }
    }

    @Test
    func rejectsMissingDuplicateAndTrailingFields() throws {
        let noData = ESMFixture.field("EDID", ESMFixture.zstring("fSpeed"))
        #expect(throws: GameSettingError.missingField("DATA")) {
            try decode(fieldData: noData)
        }
        let duplicate = noData
            + ESMFixture.field("DATA", scalar(Float(1).bitPattern))
            + ESMFixture.field("DATA", scalar(Float(2).bitPattern))
        #expect(throws: GameSettingError.duplicateField("DATA")) {
            try decode(fieldData: duplicate)
        }
        let trailingEditorID = ESMFixture.field("EDID", ESMFixture.zstring("fSpeed") + Data([9]))
            + ESMFixture.field("DATA", scalar(Float(1).bitPattern))
        #expect(throws: GameSettingError.invalidString(editorID: "EDID")) {
            try decode(fieldData: trailingEditorID)
        }
    }

    private func setting(
        _ editorID: String,
        data: Data,
        localized: Bool = false
    ) throws -> GameSetting {
        try decode(
            fieldData: ESMFixture.field("EDID", ESMFixture.zstring(editorID))
                + ESMFixture.field("DATA", data),
            localized: localized
        )
    }

    private func decode(fieldData: Data, localized: Bool = false) throws -> GameSetting {
        let plugin = try ESMFile(data: ESMFixture.tes4() + ESMFixture.topGroup(
            "GMST",
            contents: ESMFixture.record("GMST", data: fieldData)
        ))
        let group = try #require(plugin.topGroup(of: "GMST"))
        let children = try group.children()
        guard case let .record(record) = try #require(children.first) else {
            Issue.record("GMST fixture did not produce a record")
            throw ESMError.malformed("missing synthetic GMST")
        }
        return try GameSetting(record: record, localized: localized)
    }

    private func scalar(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return data
    }
}
