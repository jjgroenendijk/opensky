// The ragdoll world runs the coordinator's commands and reads bodies, health, and deaths.

import OpenSkyCombat
import OpenSkyCombatAdapters
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkySessionTesting
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
        #expect(host.fakeStreamer.takeRiddenActorCalls == [Self.actor])
        #expect(host.fakeStreamer.steerRiddenActorCalls.count == 1)
        #expect(host.fakeStreamer.releaseRiddenActorCalls == [Self.actor])
    }

    @Test func thePlayerKnockdownNeedsASession() {
        adapter.run([
            .enterKnockdown(.player), .getUp(.player, feet: .zero, yaw: nil), .endKnockdown(.player)
        ])
        #expect(graphs.raiseCalls.isEmpty)
        #expect(host.fakeStreamer.releaseRiddenActorCalls.isEmpty)
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
        _ = adapter.ragdollStepWorld
    }

    @Test func remainsWithoutRecordsKeepTheCorpseAndShowDefaultBlood() {
        #expect(!adapter.dropWeapon(of: Self.actor))
        #expect(adapter.severableNode(of: Self.actor) == nil)
        #expect(adapter.isCorpseKept(Self.actor))
        adapter.removeCorpse(Self.actor)
        adapter.showDismemberment(of: Self.actor, node: "NPC Head", at: .zero)
        #expect(host.fakeEffects.showDefaultBloodCalls.count == 1)
    }

    @Test func aDeathIsReportedToTheStoryAndMagic() {
        #expect(adapter.queueActorDeathEvents(for: Self.actor, killer: .player) == 0)
        #expect(host.fakeStoryWorld.reportKillCalls.map(\.victim) == [Self.actor])
        #expect(host.fakeMagic.noteDeathCalls.map(\.victim) == [Self.actor])
        #expect(adapter.selectedRagdollActor == nil)
        #expect(adapter.playerFeetPosition == nil)
        #expect(!adapter.searchCorpse(Self.actor))
    }
}
