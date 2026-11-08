// PRUL chunk: god mode and the crime-report switch come back as a script left them;
// standard switches write no chunk.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkySave
import OpenSkySaveFixtures
@testable import OpenSkyWorldState
import Testing

@MainActor
struct PlayerRulesSaveTests {
    @Test func switchedRulesSurviveAnEncodeAndDecode() throws {
        let rules = PlayerRuleSwitches(godMode: true, reportsCrime: false)
        let original = OpenSkySaveFixture.snapshot(
            [OpenSkySaveFixture.entry(key: .player, cell: nil, components: [rules.erased])],
            bystanderCell: OpenSkySaveFixture.riverwood
        )
        let data = OpenSkySaveFixture.encode(original)
        #expect(data.range(of: Data("PRUL".utf8)) != nil)
        let file = try OpenSkySaveDecoder.decode(data)
        #expect(file.snapshot == original)
        let store = WorldStateStore()
        store.restore(from: file.snapshot)
        #expect(store.playerRules == rules)
    }

    @Test func standardRulesLeaveNoComponent() {
        let store = WorldStateStore()
        store.playerRules.godMode = true
        #expect(store.component(PlayerRuleSwitches.self, for: .player) != nil)
        store.playerRules.godMode = false
        #expect(store.component(PlayerRuleSwitches.self, for: .player) == nil)
        let data = OpenSkySaveFixture.encode(
            OpenSkySaveFixture.snapshot([], bystanderCell: OpenSkySaveFixture.riverwood)
        )
        #expect(data.range(of: Data("PRUL".utf8)) == nil)
    }

    @Test func aShortEntryIsRejected() {
        var payload = Data()
        payload.appendUInt32(1)
        payload.append(contentsOf: [1, 0, 0, 0, 0, 0, 0, 0, 1])
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveStoryDecoder.decodePlayerRules(payload)
        }
    }
}
