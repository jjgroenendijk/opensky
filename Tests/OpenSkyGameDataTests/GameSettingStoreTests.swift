// Cross-plugin GMST precedence over synthetic plugins. Later valid values win;
// malformed records never erase the last usable setting.

import FormatsTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

struct GameSettingStoreTests {
    @Test
    func laterValidOverrideWinsByEditorIDNotFormID() throws {
        let base = try GameSettingFixture.plugin(
            editorID: "fMoveCharWalkBase",
            value: 100,
            formID: 0x10
        )
        let override = try GameSettingFixture.plugin(
            editorID: "fMoveCharWalkBase",
            value: 155,
            formID: 0x99
        )
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
        let base = try GameSettingFixture.plugin(
            editorID: "fMoveCharWalkBase",
            value: 100,
            formID: 1
        )
        let malformed = try GameSettingFixture.plugin(
            editorID: "fMoveCharWalkBase",
            rawData: Data([0, 0, 0]),
            formID: 2
        )
        let store = GameSettingStore(plugins: [("Base.esm", base), ("Broken.esp", malformed)])
        #expect(store.setting(editorID: "fMoveCharWalkBase")?.setting.value == .float(100))
        #expect(store.setting(editorID: "fMissing") == nil)
    }
}
