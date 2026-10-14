// SCRS chunk: the flags, values, form links, and added forms a script set come back
// as they were, and a session where no script set any writes no chunk.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkySave
import OpenSkySaveFixtures
import OpenSkyScriptingInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct ScriptedStateSaveTests {
    private let actor = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_2345)
    private let list = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0002_0001)
    private let faction = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_3794)

    private func snapshot() -> WorldStateSnapshot {
        let state = ScriptedReferenceState(
            flags: ["ghost": true, "Alerted": true],
            values: ["SetAlpha": 0.25, "keywordData:skyrim.esm:0001": -3],
            forms: ["crimeFaction": faction]
        )
        let added = ScriptedReferenceState(addedForms: [actor, faction, .player])
        return OpenSkySaveFixture.snapshot(
            [
                OpenSkySaveFixture.entry(
                    key: actor, cell: OpenSkySaveFixture.whiterun, components: [state.erased]
                ),
                OpenSkySaveFixture.entry(key: list, cell: nil, components: [added.erased])
            ],
            bystanderCell: OpenSkySaveFixture.riverwood
        )
    }

    @Test func scriptStateSurvivesAnEncodeAndDecode() throws {
        let original = snapshot()
        let data = OpenSkySaveFixture.encode(original)
        #expect(data.range(of: Data("SCRS".utf8)) != nil)
        let file = try OpenSkySaveDecoder.decode(data)
        #expect(file.snapshot == original)
        let store = WorldStateStore()
        store.restore(from: file.snapshot)
        let state = try #require(store.component(ScriptedReferenceState.self, for: actor))
        #expect(state.flag("GHOST") == true)
        #expect(state.flag("alerted") == true)
        #expect(state.value("setalpha") == 0.25)
        #expect(state.form("CrimeFaction") == faction)
        #expect(store.component(ScriptedReferenceState.self, for: list)?.addedForms
            == [actor, faction, .player])
    }

    @Test func noScriptStateWritesNoChunk() {
        let data = OpenSkySaveFixture.encode(
            OpenSkySaveFixture.snapshot([], bystanderCell: OpenSkySaveFixture.riverwood)
        )
        #expect(data.range(of: Data("SCRS".utf8)) == nil)
    }
}
