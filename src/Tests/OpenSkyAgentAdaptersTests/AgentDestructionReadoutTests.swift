// `state destruction` lists the newest explosions, the placed runes, and whether a kill
// cam plays; a session without a script bridge lists no objects.

import Foundation
import OpenSkyAgentAdapters
import OpenSkyAgentControl
import OpenSkyCombatInterface
import OpenSkyFormatsESM
@testable import OpenSkyMagicInterface
import OpenSkySessionTesting
import Testing

@MainActor
struct AgentDestructionReadoutTests {
    private let host = AgentHost()

    private var world: AgentWorldAdapter {
        AgentWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
    }

    @Test func theReadListsBlastsRunesAndTheKillCam() throws {
        var report = ExplosionReport(
            name: "FireBlast", cause: .projectile, position: [1, 2, 3],
            damaged: [.generated(4): 12], soundsPlayed: 1, imageSpaceStrength: nil,
            hazardPlaced: false, debrisThrown: 2
        )
        report.objectsDamaged = [.generated(5): 40]
        report.enchanted = [.generated(4)]
        host.fakeCombat.explosions.reports = [report]
        host.fakeMagic.runeMarkers = [RuneMarker(position: [4, 5, 6], projectile: nil, isLit: true)]
        host.fakeCinematicCamera.isPlaying = true
        host.fakeCinematicCamera.playedCount = 2
        host.fakeCinematicCamera.lastOutcome = "a kill cam already plays"

        let reply = try world.query(.destruction)

        #expect(reply.value(atPath: "objects") == .array([]))
        #expect(reply.value(atPath: "explosions.0.name") == .string("FireBlast"))
        #expect(reply.value(atPath: "explosions.0.debrisThrown") == .init(2))
        #expect(reply.value(atPath: "explosions.0.objectsDamaged") == .object([
            ReferenceKey.generated(5).description: .init(Float(40))
        ]))
        #expect(reply.value(atPath: "explosions.0.enchanted") == .array([
            .string(ReferenceKey.generated(4).description)
        ]))
        #expect(reply.value(atPath: "runes.0.lit") == .bool(true))
        #expect(reply.value(atPath: "killCamPlaying") == .bool(true))
        #expect(reply.value(atPath: "killCamsPlayed") == .init(2))
        #expect(reply.value(atPath: "killCamOutcome") == .string("a kill cam already plays"))
    }
}
