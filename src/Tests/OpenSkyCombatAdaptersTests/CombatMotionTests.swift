// The combat world moves actors, drives their graphs, and plays impacts through its ports.

import OpenSkyBehavior
import OpenSkyCombatAdapters
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkySessionTesting
import OpenSkyWorldInterface
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

    @Test func movesGoThroughTheStreamer() {
        host.fakeStreamer.actors.moveActorResult = .started
        #expect(adapter.moveActor(Self.foe, to: SIMD3(1, 2, 3)))
        #expect(adapter.moveActor(Self.foe, to: SIMD3(1, 2, 3), gait: nil))
        #expect(host.fakeStreamer.actors.moveActorCalls.count == 2)
        adapter.faceActor(Self.foe, toward: .zero)
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
    }

    @Test func withoutASessionThePlayerGraphIsUntouched() {
        #expect(!adapter.raisePlayerGraphEvent("attackStart"))
        adapter.writePlayerGraphVariable(.bool(true), named: "IsAttacking")
    }

    @Test func withoutFootstepRecordsThereIsNoImpact() {
        #expect(adapter.impact(dataSet: FormID(0x10), material: nil) == nil)
        #expect(adapter.impact(dataSetEditorID: "WPNBlade1HandImpactSet", material: nil) == nil)
    }
}
