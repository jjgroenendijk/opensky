// The ragdoll world runs the coordinator's commands and reads bodies, health, and deaths.

import OpenSkyCombat
import OpenSkyCombatAdapters
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkySessionTesting
import OpenSkyWorldState
import simd
import Testing

@MainActor
struct RagdollWorldTests {
    private let host = CombatHost()
    private let graphs = FakeActorGraphPort()
    private var adapter: RagdollWorldAdapter {
        RagdollWorldAdapter(game: host)
    }

    private static let actor = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)

    init() {
        host.fakeActorGraphWorld.graphs = graphs
    }

    @Test func withoutRecordsThereIsNoSessionData() {
        #expect(adapter.sessionData() == nil)
    }

    @Test func aMurderIsReportedAndTheKillCamTold() {
        adapter.run([.reportMurder(Self.actor)])
        #expect(host.fakeCrime.reportMurderCalls == [Self.actor])
        #expect(host.fakeCinematicWorld.actorDiedCalls == [Self.actor])
    }

    @Test func aPlayerRagdollWithoutABodyIsDropped() {
        adapter.run([.publishPlayerRagdoll(["NPC Head": matrix_identity_float4x4])])
        #expect(host.fakeCrime.reportMurderCalls.isEmpty)
    }

    @Test func bleedoutAndKnockdownRaiseTheActorGraph() {
        adapter.run([
            .enterBleedout(Self.actor), .leaveBleedout(Self.actor), .enterKnockdown(Self.actor),
            .getUp(Self.actor, feet: SIMD3(1, 2, 3), yaw: 0.5), .endKnockdown(Self.actor)
        ])
        #expect(graphs.raiseCalls.map(\.event) == [
            RagdollGraphNames.bleedOutStart, RagdollGraphNames.bleedOutStop,
            RagdollGraphNames.ragdollInstant, RagdollGraphNames.getUpStart
        ])
        #expect(host.fakeStreamer.actors.takeRiddenActorCalls == [Self.actor])
        #expect(host.fakeStreamer.actors.steerRiddenActorCalls.count == 1)
        #expect(host.fakeStreamer.actors.releaseRiddenActorCalls == [Self.actor])
    }

    @Test func thePlayerKnockdownNeedsASession() {
        adapter.run([
            .enterKnockdown(.player), .getUp(.player, feet: .zero, yaw: nil), .endKnockdown(.player)
        ])
        #expect(graphs.raiseCalls.isEmpty)
        #expect(host.fakeStreamer.actors.releaseRiddenActorCalls.isEmpty)
    }

    @Test func withoutABridgeAZeroHealthActorDies() {
        #expect(adapter.zeroHealthOutcome(of: Self.actor, killer: .player) == .dies)
        #expect(!adapter.blocksBleedoutRecovery(of: Self.actor))
        #expect(adapter.healthFraction(of: Self.actor) == nil)
        #expect(adapter.bleedoutThreshold(of: Self.actor) == nil)
        adapter.restoreHealthShare(0.5, of: Self.actor)
        #expect(adapter.getUpDuration(of: Self.actor) == nil)
        #expect(adapter.getUpDuration(of: .player) == nil)
    }

    @Test func poseReadsNeedLoadedActors() {
        host.fakeStreamer.residentCellLocations = [.interior(FormID(0x100))]
        #expect(adapter.residentRagdollCells == [.interior(FormID(0x100))])
        #expect(adapter.holder(of: .player) == .player)
        #expect(adapter.holder(of: Self.actor) == nil)
        #expect(!adapter.hasZeroHealth(Self.actor))
        #expect(adapter.ragdollPose(of: Self.actor) == nil)
        #expect(adapter.ragdollPose(of: .player) == nil)
        #expect(adapter.animatedPose(of: .player) == nil)
        #expect(adapter.animatedPose(of: Self.actor) == nil)
        #expect(!adapter.raisePlayerGraphEvent("GetUpStart"))
        adapter.restartPlayerGraph()
        _ = adapter.ragdollStepWorld
    }

    @Test func aDeathResetRestartsThePlayersGraphs() {
        let session = FakeGameSessionPort()
        let locomotion = FakeLocomotionBridgePort()
        session.locomotion = locomotion
        host.gameSession = session
        adapter.restartPlayerGraph()
        #expect(locomotion.restartGraphsCallCount == 1)
    }

    /// A walked actor's bodies spawn where it walked to, at its drawn height.
    @Test func theRagdollFrameIsWhereAndHowBigTheActorDraws() {
        let placed = PlacedReference.Placement(position: SIMD3(0, 0, 0), rotation: .zero)
        let moved = ReferenceTransformOverride(
            placement: PlacedReference.Placement(position: SIMD3(800, 0, 0), rotation: .zero),
            scale: 1
        )
        let frame = ActorDrawnFrame(
            placed: placed, scale: 1, moved: moved, height: 1.3
        )
        #expect(frame.scale == 1.3)
        #expect(frame.actorToWorld.columns.3.x == 800)
        #expect(abs(frame.actorToWorld.columns.0.x - 1.3) < 1e-5)
        let still = ActorDrawnFrame(
            placed: placed, scale: 2, moved: nil, height: 1
        )
        #expect(still.scale == 2)
        #expect(still.actorToWorld.columns.3.x == 0)
    }

    @Test func remainsWithoutRecordsKeepTheCorpseAndShowDefaultBlood() {
        #expect(!adapter.dropWeapon(of: Self.actor))
        #expect(adapter.severableNode(of: Self.actor) == nil)
        #expect(adapter.isCorpseKept(Self.actor))
        adapter.removeCorpse(Self.actor)
        adapter.showDismemberment(of: Self.actor, node: "NPC Head", at: .zero)
        #expect(host.fakeEffects.showDefaultBloodCalls.count == 1)
        #expect(adapter.explodablePart(of: Self.actor) == nil)
        adapter.showPartExplosion(of: Self.actor, node: "NPC Head", at: .zero)
        #expect(host.fakeEffectsWorld.detonateEffectExplosionCalls.isEmpty)
    }

    @Test func aDeathIsReportedToTheStoryAndMagic() {
        #expect(adapter.queueActorDeathEvents(for: Self.actor, killer: .player) == 0)
        #expect(host.fakeStoryWorld.reportKillCalls.map(\.victim) == [Self.actor])
        #expect(host.fakeMagic.soulTrapping.noteDeathCalls.map(\.victim) == [Self.actor])
        #expect(adapter.selectedRagdollActor == nil)
        #expect(adapter.playerFeetPosition == nil)
        #expect(!adapter.searchCorpse(Self.actor))
    }

    @Test func aKillByThePlayerCountsTheVictimsActorTypes() {
        host.fakeMagicWorld.actorHasKeywordResult = true
        _ = adapter.queueActorDeathEvents(for: .player, killer: .player)
        #expect(host.fakeWorldState.incrementMiscStatCalls.map(\.name) == [
            "People Killed", "Animals Killed", "Undead Killed", "Daedra Killed",
            "Automatons Killed"
        ])
        host.fakeWorldState.incrementMiscStatCalls = []
        _ = adapter.queueActorDeathEvents(for: .player, killer: Self.actor)
        #expect(host.fakeWorldState.incrementMiscStatCalls.isEmpty, "only the player's kills count")
    }

    @Test func aBeastFormKillOfABunnyMaulsAndCountsTheBunny() {
        let bridge = FakePapyrusWorldStateBridgePort()
        host.fakeScripts.bridge = bridge
        bridge.isInFactionResult = true
        bridge.scriptedStateResult = ScriptedReferenceState(
            flags: [ScriptedStateName.beastForm: true]
        )
        let records = FakeCombatRecords()
        records.miscStatSources = MiscStatSources(bunnyFaction: .generated(9))
        host.combatRecords = records
        host.fakeMagicWorld.actorHasKeywordResult = false
        _ = adapter.queueActorDeathEvents(for: .player, killer: .player)
        #expect(host.fakeWorldState.incrementMiscStatCalls.map(\.name) == [
            "Mauls", "Bunnies Slaughtered"
        ])
        #expect(bridge.isInFactionCalls.map(\.faction) == [.generated(9)])
    }
}
