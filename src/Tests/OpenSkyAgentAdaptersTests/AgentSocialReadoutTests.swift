// The reads that explain a fight: the hostility terms of an actor in `state actors`, and
// the last killing swing with no kill move in `state paired`.

import Foundation
import OpenSkyActorsInterface
import OpenSkyAgentAdapters
import OpenSkyAgentControl
import OpenSkyCombatInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkyRenderCore
import OpenSkySessionInterface
import OpenSkySessionTesting
import OpenSkyWorldInterface
import OpenSkyWorldState
import Testing

@MainActor
struct AgentSocialReadoutTests {
    private let host = AgentHost()
    private let world: AgentWorldAdapter

    init() {
        world = AgentWorldAdapter(game: host, now: { Date(timeIntervalSinceReferenceDate: 0) })
    }

    private func object(_ json: AgentJSON?) -> [String: AgentJSON] {
        guard case let .object(fields)? = json else { return [:] }
        return fields
    }

    @Test func aDetailedActorShowsItsHostilityTerms() throws {
        let session = FakeGameSessionPort()
        session.freeFlyCameraValue = FreeFlyCamera(position: [0, 0, 0], yaw: 0, pitch: 0)
        host.gameSession = session
        host.fakeFactions.hostilityResult = .neutral
        host.fakeEffects.skinDecalsValue = SkinDecalRuntime()
        host.fakeStreamer.dynamicBodiesValue = DynamicBodyWorld()
        let bandits = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x1BCC0)
        host.fakeFactions.profileResult = ActorSocialProfile(
            key: .generated(9),
            memberships: ActorFactionState(memberships: [
                ActorFactionMembership(faction: bandits, rank: 0)
            ])
        )
        host.fakeActorWorld.combatActorsResult = [
            CombatActorObservation(key: .generated(9), feet: [10, 0, 0], name: "bandit")
        ]
        let state = try object(world.query(.actors(radius: 1024, detailed: 1)))
        guard case let .array(rows)? = state["actors"], let row = rows.first else {
            Issue.record("no actor list")
            return
        }
        let social = object(object(row)["social"])
        #expect(social["factions"] == .array([.string("\(bandits)")]))
        #expect(social["playerFactions"] == .array([.string("\(bandits)")]))
        #expect(social["override"] == .null)
    }

    @Test func thePairedStateListsTheIdlesOfAMissedKillMove() throws {
        let idle = ResolvedFormID(plugin: "Skyrim.esm", objectID: 0x24CD4)
        let idles = FakeIdlePort()
        idles.lastKillMoveMiss = KillMoveMiss(
            attacker: .generated(9), target: .player, action: "ActionRightPowerAttack",
            trace: [
                IdleCandidateTrace(
                    id: idle, editorID: "KillMoveFrontSideRoot", depth: 0,
                    verdict: .rejected("GetTargetHeight")
                ),
                IdleCandidateTrace(id: idle, editorID: nil, depth: 1, verdict: .notReached)
            ]
        )
        host.fakeIdleWorld.idles = idles
        let miss = try object(object(world.query(.paired))["lastKillMoveMiss"])
        #expect(miss["action"] == .string("ActionRightPowerAttack"))
        #expect(miss["idles"] == .array([
            .string("KillMoveFrontSideRoot: rejected(\"GetTargetHeight\")")
        ]))
    }
}
