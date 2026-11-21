// `openskycli game state stats` lists the journal stats counted so far.

import Foundation
import OpenSkyAgentAdapters
import OpenSkyAgentControl
import OpenSkyQuestsInterface
import OpenSkySessionTesting
import Testing

@MainActor
struct AgentStatsReadTests {
    @Test func theStatsReadListsTheCountedStats() throws {
        let host = AgentHost()
        host.fakeWorldState.miscStatsValue = MiscStatsState(
            values: ["Locks Picked": 3, "Barters": 0]
        )
        host.fakeMenuWorld.journalFavoritesResult = ["Favorite Shout": "Unrelenting Force"]
        let world = AgentWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
        let args = AgentArguments(command: "state.stats", values: [:])
        #expect(try AgentStateQuery.parse("stats", args) == .stats)
        guard case let .object(state) = try world.query(.stats) else {
            Issue.record("the stats read is not an object")
            return
        }
        #expect(state["stats"] == ["Locks Picked": .init(3)])
        #expect(state["favorites"] == ["Favorite Shout": "Unrelenting Force"])
    }
}
