// `state assist` over a fake combat port: each helper rule's rows reach the reply.

import Foundation
import OpenSkyAgentAdapters
import OpenSkyAgentControl
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkySessionTesting
import Testing

@MainActor
struct AgentAssistReadoutTests {
    private let host = AgentHost()

    private var world: AgentWorldAdapter {
        AgentWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
    }

    @Test func theAssistReadListsTracksWatchesAndProcessLevels() throws {
        var readout = CombatAssistReadout()
        readout.tracks = [
            .init(attacker: .generated(1), target: .player, aim: [1, 2, 3], refreshes: 4)
        ]
        var watch = CombatDangerWatch()
        watch.score = 0.5
        watch.dodgeCount = 2
        readout.watches = [.generated(1): watch]
        host.fakeCombat.assistReadoutValue = readout
        host.fakePackages.processReadout = ["high": 3]
        let reply = try world.query(.assist)
        #expect(reply.value(atPath: "attackTracks.0.refreshes") == .init(4))
        #expect(reply.value(atPath: "danger.watches.0.dodges") == .init(2))
        #expect(reply.value(atPath: "danger.threats") == .array([]))
        #expect(reply.value(atPath: "autoAim") == .null)
        #expect(reply.value(atPath: "processLevels.high") == .number(3))
    }
}
