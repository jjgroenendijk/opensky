// The summoned actors part places, enlists, and dismisses the actors a spell commands.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyMagicAdapters
import OpenSkyMagicInterface
import OpenSkyScriptingInterface
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
        #expect(adapter
            .summonActor(FormID(0x30), at: .ahead(searchRadius: 512), for: Self.actor) == nil)
        #expect(host.fakeWorldState.setCalls.isEmpty)
    }

    /// A summon is a loud sound of its caster at the place of the summon.
    @Test func aSummonLeavesALoudSoundEvent() {
        let perception = FakePerceptionRuntimePort()
        host.fakePerception.runtime = perception
        host.fakeGameSession = FakeGameSessionPort()
        host.fakeStreamer.currentCellLocation = Self.cell
        host.fakeWorldState.allocateGeneratedKeyResult = .generated(9)
        let point = SIMD3<Float>(40, 0, 0)
        #expect(adapter.summonActor(FormID(0x30), at: .point(point), for: .player) != nil)
        #expect(perception.noteSummonCalls.map(\.position) == [point])
        #expect(perception.noteSummonCalls.map(\.caster) == [.player])
    }

    /// A self-cast summon stands ahead of the player, along the player's facing, and turns
    /// back to face the player.
    @Test func aSelfCastSummonStandsAheadOfThePlayer() throws {
        host.fakeGameSession = FakeGameSessionPort()
        host.fakeStreamer.currentCellLocation = Self.cell
        host.fakeWorldState.allocateGeneratedKeyResult = .generated(9)
        host.fakeCombat.meleeAttacker = MeleeAttacker(key: .player, feet: .zero, facing: 0)
        #expect(adapter.summonActor(FormID(0x30), at: .ahead(searchRadius: 512), for: .player)
            == .generated(9))
        let spawn = try #require(host.fakeWorldState.setCalls.compactMap {
            $0.component as? ReferenceSpawnState
        }.first)
        #expect(spawn.placement.position.x == 256)
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

    @Test func spendingASoulOnANewWordCountsItUnlocked() {
        let bridge = FakePapyrusWorldStateBridgePort()
        host.fakeScripts.bridge = bridge
        bridge.scriptedStateResult = ScriptedReferenceState()
        adapter.changeShoutKnowledge(.unlockWord(Self.actor))
        #expect(host.fakeWorldState.incrementMiscStatCalls
            .map(\.name) == ["Words Of Power Unlocked"])
        bridge.scriptedStateResult = ScriptedReferenceState(
            flags: [ScriptedStateName.wordUnlocked(Self.actor): true]
        )
        adapter.changeShoutKnowledge(.unlockWord(Self.actor))
        #expect(host.fakeWorldState.incrementMiscStatCalls.count == 1, "a word unlocks once")
    }
}
