// The combat world moves actors, drives their graphs, and plays impacts through its ports.

import OpenSkyBehavior
@testable import OpenSkyCombatAdapters
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkySessionTesting
import OpenSkyWorldInterface
import OpenSkyWorldState
import Testing

@MainActor
struct CombatMotionTests {
    private let host = CombatHost()
    private var adapter: CombatWorldAdapter {
        CombatWorldAdapter(game: host)
    }

    private static let foe = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)

    @Test func aPackageOrDisabledAIKeepsAnActorOutOfCombat() {
        #expect(!adapter.packageIgnoresCombat(Self.foe))
        host.fakeAiWorld.isAIDisabledResult = true
        #expect(adapter.packageIgnoresCombat(Self.foe))
        host.fakeAiWorld.isAIDisabledResult = false
        host.fakePackages.ignoresCombatResult = true
        #expect(adapter.packageIgnoresCombat(Self.foe))
    }

    /// `BoundArrowPROJ` sets only Can Be Disabled: a use of a stuck one takes nothing.
    @Test func aStuckProjectileThatCannotBePickedUpRefusesTheUse() {
        let archery = FakeArcheryRuntimePort()
        host.fakeCombat.archery = archery
        let stuck = FormID(0xFF00_0007)
        #expect(adapter.stuckProjectileRefusal(for: stuck) == nil)

        archery.projectiles.activateStuckResult = StuckProjectileUse(
            allowsPickUp: false, disableSound: FormID(0x0005_5555), position: .zero
        )
        #expect(adapter.stuckProjectileRefusal(for: stuck) == .inert)
        #expect(adapter.stuckProjectileRefusal(for: FormID(0x0001_397D)) == nil)
        #expect(archery.projectiles.activateStuckCalls == [.generated(7), .generated(7)])

        archery.projectiles.activateStuckResult = StuckProjectileUse(
            allowsPickUp: true, disableSound: nil, position: .zero
        )
        #expect(adapter.stuckProjectileRefusal(for: stuck) == nil)
    }

    @Test func theStuckProjectileCheckJoinsTheActivationGate() {
        let seam = FakeActivationGateSeamPort()
        host.fakeStreamer.activationGate = seam
        adapter.frames.registerStuckProjectileUse()
        #expect(seam.registerCalls == [.projectile])
    }

    @Test func movesGoThroughTheStreamer() {
        host.fakeStreamer.actors.moveActorResult = .started
        #expect(adapter.moveActor(Self.foe, to: SIMD3(1, 2, 3)))
        #expect(adapter.moveActor(Self.foe, to: SIMD3(1, 2, 3), pace: nil))
        #expect(adapter.moveActor(Self.foe, to: SIMD3(1, 2, 3), pace: .run))
        #expect(adapter.moveActor(Self.foe, to: SIMD3(1, 2, 3), pace: .fastWalk))
        #expect(host.fakeStreamer.actors.moveActorCalls.count == 4)
        adapter.faceActor(Self.foe, toward: .zero)
        adapter.lookActor(Self.foe, at: .player, seconds: 5)
        #expect(host.fakeHeadTracking.setLookTargetCalls.map(\.target) == [.player])
        #expect(host.fakeHeadTracking.setLookTargetCalls.map(\.seconds) == [5])
        adapter.stopActor(Self.foe)
        adapter.resumePackage(for: Self.foe)
        #expect(host.fakeStreamer.actors.faceActorCalls.map(\.actor) == [Self.foe])
        #expect(host.fakeStreamer.actors.stopActorCalls == [Self.foe])
        #expect(host.fakePackages.resumeCalls == [Self.foe])
    }

    @Test func actorGraphEventsAndVariablesReachTheGraphs() {
        host.fakeActorGraphs.raiseResult = true
        #expect(adapter.raiseActorGraphEvent("staggerStart", on: Self.foe))
        adapter.writeActorGraphVariable(.real(1), named: "staggerMagnitude", on: Self.foe)
        #expect(host.fakeActorGraphs.raiseCalls.map(\.event) == ["staggerStart"])
        #expect(host.fakeActorGraphs.setVariableCalls.map(\.name) == ["staggerMagnitude"])
        host.fakeActorGraphs.variableResult = .bool(true)
        #expect(adapter.actorGraphVariable(named: "IsAttackReady", on: Self.foe) == .bool(true))
        #expect(adapter.motion
            .actorGraphVariable(named: "IsEquipping", on: Self.foe) == .bool(true))
        #expect(host.fakeActorGraphs.variableCalls.map(\.name) == ["IsAttackReady", "IsEquipping"])
    }

    @Test func withoutASessionThePlayerGraphIsUntouched() {
        #expect(!adapter.raisePlayerGraphEvent("attackStart"))
        adapter.writePlayerGraphVariable(.bool(true), named: "IsAttacking")
    }

    @Test func aStuckArrowIsHeldInPlace() {
        let arrow = ReferenceSpawnState(
            base: FormID(0x1397D), location: .interior(FormID(0x165A7)),
            placement: PlacedReference.Placement(position: .zero, rotation: .zero)
        )
        host.fakeWorldState.allocateGeneratedKeyResult = .generated(7)
        #expect(adapter.spawn(arrow, in: arrow.location) == .generated(7))
        let motion = host.fakeWorldState.setCalls.compactMap {
            $0.component as? ReferenceMotionType
        }
        #expect(motion == [.keyframed])
    }

    @Test func withoutFootstepRecordsThereIsNoImpact() {
        #expect(adapter.impact(dataSet: FormID(0x10), material: nil) == nil)
        #expect(adapter.impact(dataSetEditorID: "WPNBlade1HandImpactSet", material: nil) == nil)
    }
}
