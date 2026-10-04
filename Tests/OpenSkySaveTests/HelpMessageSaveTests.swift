// HELP chunk: help-message counts on the player come back as they were; a
// session that showed none writes no chunk.

import FormatsCoreTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkySave
import OpenSkySaveFixtures
import OpenSkyScriptingInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct HelpMessageSaveTests {
    private let state = HelpMessageState(records: [
        "jump": HelpMessageRecord(timesShown: 2, isDone: false),
        "sneak": HelpMessageRecord(timesShown: 1, isDone: true)
    ])

    @Test func countsSurviveAnEncodeAndDecode() throws {
        let original = OpenSkySaveFixture.snapshot(
            [OpenSkySaveFixture.entry(key: .player, cell: nil, components: [state.erased])],
            bystanderCell: OpenSkySaveFixture.riverwood
        )
        let data = OpenSkySaveFixture.encode(original)
        #expect(data.range(of: Data("HELP".utf8)) != nil)
        let file = try OpenSkySaveDecoder.decode(data)
        #expect(file.snapshot == original)
        let store = WorldStateStore()
        store.restore(from: file.snapshot)
        #expect(store.component(HelpMessageState.self, for: .player) == state)
    }

    @Test func noHelpMessageWritesNoChunk() {
        let data = OpenSkySaveFixture.encode(
            OpenSkySaveFixture.snapshot([], bystanderCell: OpenSkySaveFixture.riverwood)
        )
        #expect(data.range(of: Data("HELP".utf8)) == nil)
    }

    @Test func recordCountPastThePayloadIsRejected() {
        var payload = Data()
        payload.appendUInt32(1)
        payload.append(contentsOf: [1, 0, 0, 0, 0, 0, 0, 0])
        payload.appendUInt32(1_000_000)
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveStoryDecoder.decodeHelpMessages(payload)
        }
    }
}
