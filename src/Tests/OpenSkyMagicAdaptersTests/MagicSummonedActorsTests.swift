// The summoned actors part places, enlists, and dismisses the actors a spell commands.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyMagicAdapters
import OpenSkyMagicInterface
import OpenSkySessionTesting
import OpenSkyWorldInterface
import OpenSkyWorldState
import Testing

@MainActor
struct MagicSummonedActorsTests {
    private let host = MagicHost()
    private let loop = FakeCombatLoopRuntimePort()
    private var adapter: MagicWorldAdapter {
        MagicWorldAdapter(game: host)
    }

    private static let actor = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)
    private static let cell = CellSceneLocation.interior(FormID(0x10))

    init() {
        host.fakeCombat.loop = loop
    }

    @Test func theCasterWithoutFeetSummonsNothing() {
        #expect(adapter.summonActor(FormID(0x30), at: nil, for: Self.actor) == nil)
        #expect(host.fakeWorldState.setCalls.isEmpty)
    }

    @Test func thePlayersAllyIsCalmAndCommanded() {
        adapter.commandActor(Self.actor, for: .player)
        #expect(loop.setHostilityCalls.map(\.hostility) == [.neutral])
        #expect(loop.commandCalls.map(\.commander) == [.player])
    }

    @Test func anNPCsAllySharesItsCastersRegard() {
        let caster = ReferenceKey.plugin(name: "base.esm", objectID: 0x22)
        loop.hostilityResult = .hostile
        adapter.commandActor(Self.actor, for: caster)
        #expect(loop.hostilityCalls == [caster])
        #expect(loop.setHostilityCalls.map(\.hostility) == [.hostile])
    }

    @Test func aStoppedSummonIsDismissed() {
        adapter.stopCommandedActor(Self.actor)
        #expect(loop.dismissCalls == [Self.actor])
    }

    @Test func aReleasedSummonLeavesItsCell() {
        host.fakeWorldState.componentResult = ReferenceSpawnState(
            base: FormID(0x30), location: Self.cell,
            placement: PlacedReference.Placement(position: .zero, rotation: .zero)
        )
        adapter.releaseCommandedActor(CommandedActor(
            actor: Self.actor,
            caster: .player,
            kind: .summoned,
            holder: .player,
            sequence: 1
        ))
        #expect(loop.dismissCalls == [Self.actor])
        #expect(host.fakeWorldState.resetKeyCalls == [Self.actor])
        #expect(host.fakeStreamer.requestRebuildCalls == [Self.cell])
    }

    @Test func aCorpseWithoutAScriptBridgeStaysDead() {
        host.fakeActorWorld.combatActorsResult = [
            CombatActorObservation(key: Self.actor, feet: .zero, isDead: true)
        ]
        #expect(!adapter.reanimate(Self.actor, for: .player))
        adapter.releaseCommandedActor(CommandedActor(
            actor: Self.actor,
            caster: .player,
            kind: .reanimated,
            holder: .player,
            sequence: 2
        ))
        #expect(loop.dismissCalls == [Self.actor])
    }

    @Test func deathIsReadFromTheCombatActor() {
        #expect(!adapter.isActorDead(Self.actor))
        host.fakeCombat.combatActorResult = CombatActorObservation(
            key: Self.actor, feet: .zero, isDead: true
        )
        #expect(adapter.isActorDead(Self.actor))
    }

    @Test func withoutScriptsThePlayerKnowsNoShout() {
        #expect(adapter.shoutKnowledge.shouts.isEmpty)
        adapter.changeShoutKnowledge(.addShout(Self.actor))
        #expect(adapter.shoutKnowledge.shouts.isEmpty)
    }
}
