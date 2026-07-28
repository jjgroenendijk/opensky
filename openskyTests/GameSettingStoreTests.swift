// Cross-plugin GMST precedence over synthetic plugins. Later valid values win;
// malformed records never erase the last usable setting.

import Foundation
@testable import opensky
import Testing

struct GameSettingStoreTests {
    @Test
    func laterValidOverrideWinsByEditorIDNotFormID() throws {
        let base = try plugin(editorID: "fMoveCharWalkBase", value: 100, formID: 0x10)
        let override = try plugin(editorID: "fMoveCharWalkBase", value: 155, formID: 0x99)
        let store = GameSettingStore(plugins: [
            ("Skyrim.esm", base),
            ("Movement.esp", override)
        ])
        let resolved = try #require(store.setting(editorID: "FMOVECHARWALKBASE"))
        #expect(resolved.setting.value == .float(155))
        #expect(resolved.sourcePlugin == "Movement.esp")
    }

    @Test
    func malformedLaterRecordDoesNotEraseValidValueAndMissingStaysNil() throws {
        let base = try plugin(editorID: "fMoveCharWalkBase", value: 100, formID: 1)
        let malformed = try plugin(
            editorID: "fMoveCharWalkBase",
            rawData: Data([0, 0, 0]),
            formID: 2
        )
        let store = GameSettingStore(plugins: [("Base.esm", base), ("Broken.esp", malformed)])
        #expect(store.setting(editorID: "fMoveCharWalkBase")?.setting.value == .float(100))
        #expect(store.setting(editorID: "fMissing") == nil)
    }

    @Test
    func movementResolutionUsesValidFloatsAndExplicitFallbacks() throws {
        let file = try plugin(editorID: "fMoveCharWalkBase", value: 125, formID: 1)
        let configuration = PlayerMovementConfiguration.resolve(
            store: GameSettingStore(plugins: [("Tuning.esp", file)])
        )
        #expect(configuration.walkSpeed == MovementSetting(value: 125, source: "Tuning.esp"))
        #expect(configuration.runSpeed == MovementSetting(value: 370, source: "engine default"))
        #expect(configuration.stepHeight.value == 32)
        #expect(configuration.stepHeight.source.contains("no confirmed"))
    }

    private func plugin(editorID: String, value: Float, formID: UInt32) throws -> ESMFile {
        try plugin(editorID: editorID, rawData: scalar(value.bitPattern), formID: formID)
    }

    private func plugin(editorID: String, rawData: Data, formID: UInt32) throws -> ESMFile {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
            + ESMFixture.field("DATA", rawData)
        return try ESMFile(data: ESMFixture.tes4() + ESMFixture.topGroup(
            "GMST",
            contents: ESMFixture.record("GMST", formID: formID, data: fields)
        ))
    }

    private func scalar(_ value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(value)
        return data
    }
}
