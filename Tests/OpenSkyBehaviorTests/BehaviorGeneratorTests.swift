// Blend, selection, and state-machine evaluation, and the tally a class with
// no semantics leaves. Clip evaluation is in BehaviorClipTests.swift.

import Foundation
import OpenSkyBehavior
import OpenSkyEngineTesting
@testable import OpenSkyFormatsAnimation
import simd
import Testing

struct BehaviorGeneratorTests {
    // MARK: - Blending and selection

    @Test func twoChildrenBlendAtTheirNormalizedWeights() {
        var table = BehaviorObjectTable()
        let (root, _) = blendGraph(&table, firstWeight: 0.75, secondWeight: 0.25)
        let graph = BehaviorFixture.instance(
            root: root,
            table: table,
            clips: BehaviorFixture.staticClipPair(left: 0, right: 10)
        )
        // 0 + (10 - 0) * (0.25 / (0.75 + 0.25)) = 2.5.
        #expect(abs(graph.update(deltaTime: 1 / 30).bones[1].translation.x - 2.5) < 1e-4)
    }

    @Test func aBoneUnderTheReferencePoseThresholdFillsUpWithTheReferencePose() {
        var table = BehaviorObjectTable()
        let (root, _) = blendGraph(
            &table, firstWeight: 0.02, secondWeight: 0.03, threshold: 0.1
        )
        let graph = BehaviorFixture.instance(
            root: root,
            table: table,
            clips: BehaviorFixture.staticClipPair(left: 0, right: 10)
        )
        // The children give x 6 at weight 0.05; the reference (0, 10, 0) takes the other 0.05.
        let bone = graph.update(deltaTime: 1 / 30).bones[1]
        #expect(simd_distance(bone.translation, SIMD3(3, 5, 0)) < 1e-4)
    }

    @Test func smoothedWeightsEaseEachChildWeight() {
        var table = BehaviorObjectTable()
        let (root, _) = blendGraph(
            &table, firstWeight: 1, secondWeight: 0.25,
            flags: BehaviorBlenderFlag.smoothGeneratorWeights
        )
        let graph = BehaviorFixture.instance(
            root: root,
            table: table,
            clips: BehaviorFixture.staticClipPair(left: 0, right: 10)
        )
        // 0.25 eases to 0.15625, so the right clip has 0.15625 / 1.15625 of the blend.
        let expected: Float = 10 * 0.15625 / 1.15625
        #expect(abs(graph.update(deltaTime: 1 / 30).bones[1].translation.x - expected) < 1e-4)
    }

    @Test func aBoundBlendWeightMovesTheBlend() {
        var table = BehaviorObjectTable()
        let binding = table.add(
            BehaviorFixture.bindingSet([BehaviorBindingSpec("m_weight", 0)]),
            at: 0x50
        )
        let (root, _) = blendGraph(
            &table, firstWeight: 1, secondWeight: 1, secondBinding: binding
        )
        let data = BehaviorFixture.graphData(variables: [BehaviorVariableSpec("Blend", .real, 1)])
        let graph = BehaviorFixture.instance(
            root: root,
            table: table,
            data: data,
            clips: BehaviorFixture.staticClipPair(left: 0, right: 10)
        )
        #expect(abs(graph.update(deltaTime: 1 / 30).bones[1].translation.x - 5) < 1e-4)

        graph.setVariable(.real(0.2), named: "Blend")
        // 0 + 10 * (0.2 / (1 + 0.2)).
        #expect(abs(graph.update(deltaTime: 1 / 30).bones[1].translation.x - 10 / 6) < 1e-4)

        // A weight above 1 counts as 1.
        graph.setVariable(.real(3), named: "Blend")
        #expect(abs(graph.update(deltaTime: 1 / 30).bones[1].translation.x - 5) < 1e-4)
    }

    @Test func aSelectorIndexOutsideItsChildrenProducesTheReferencePose() {
        var table = BehaviorObjectTable()
        let child = table.add(
            BehaviorFixture.clipGenerator("only", animationName: "left"), at: 0x100
        )
        let root = table.add(
            BehaviorFixture.selector("select", generators: [child], selected: 4),
            at: 0x200
        )
        let graph = BehaviorFixture.instance(
            root: root,
            table: table,
            clips: BehaviorFixture.staticClipPair(left: 0, right: 10)
        )
        #expect(graph.update(deltaTime: 1 / 30).bones == BehaviorFixture.skeleton()
            .referencePose)
    }

    // MARK: - Tally

    @Test func aBehaviorReferenceIsTalliedRatherThanGuessedAt() {
        var table = BehaviorObjectTable()
        let root = table.add(
            HKBBehaviorReferenceGenerator(
                node: BehaviorFixture.nodeHeader("reference"),
                behaviorName: "0_Master.hkx",
                unresolved: []
            ),
            at: 0x100
        )
        let graph = BehaviorFixture.instance(root: root, table: table)
        #expect(graph.update(deltaTime: 1 / 30).bones == BehaviorFixture.skeleton()
            .referencePose)
        #expect(graph.tally.featureGaps["unresolvedBehaviorReference"] == 1)
        #expect(!graph.tally.isClean)
    }

    @Test func aGeneratorWithNoSemanticsIsNamedInTheTally() {
        var table = BehaviorObjectTable()
        let root = table.add(
            HKBBlendingTransitionEffect(
                node: BehaviorFixture.nodeHeader("blendIn"),
                selfTransitionMode: 0,
                eventMode: 0,
                duration: 0.2,
                toGeneratorStartTimeFraction: 0,
                flags: 0,
                endMode: 0,
                blendCurve: 0,
                unresolved: []
            ),
            at: 0x100
        )
        let graph = BehaviorFixture.instance(root: root, table: table)
        graph.update(deltaTime: 1 / 30)
        #expect(
            graph.tally.unevaluatedGenerators["hkbBlendingTransitionEffect"] == 1
        )
    }

    @Test func aStateMachineRunsItsStartState() {
        var table = BehaviorObjectTable()
        let clip = table.add(
            BehaviorFixture.clipGenerator("idle", animationName: "right"), at: 0x100
        )
        let state = table.add(
            HKBStateMachineStateInfo(
                variableBindingSet: nil,
                enterNotifyEvents: nil,
                exitNotifyEvents: nil,
                transitions: nil,
                generator: clip,
                name: "Idle",
                stateId: 4,
                probability: 1,
                enable: true,
                unresolved: []
            ),
            at: 0x200
        )
        let root = table.add(stateMachine(states: [state], startStateId: 4), at: 0x300)
        let graph = BehaviorFixture.instance(
            root: root,
            table: table,
            clips: BehaviorFixture.staticClipPair(left: 0, right: 10)
        )
        #expect(graph.update(deltaTime: 1 / 30).bones[1].translation.x == 10)
        #expect(graph.activeStates.map(\.stateName) == ["Idle"])
    }

    // MARK: - Helpers

    private func stateMachine(
        states: [HKXPointerTarget?],
        startStateId: Int
    ) -> HKBStateMachine {
        HKBStateMachine(
            node: BehaviorFixture.nodeHeader("machine"),
            eventToSendWhenStateOrTransitionChanges: HKBEventProperty(
                id: -1, payload: nil
            ),
            startStateChooser: nil,
            startStateId: startStateId,
            returnToPreviousStateEventId: -1,
            randomTransitionEventId: -1,
            transitionToNextHigherStateEventId: -1,
            transitionToNextLowerStateEventId: -1,
            syncVariableIndex: -1,
            wrapAroundStateId: false,
            maxSimultaneousTransitions: 1,
            startStateMode: 0,
            selfTransitionMode: 0,
            states: states,
            wildcardTransitions: nil,
            unresolved: []
        )
    }

    /// A two-child blender over the `left` and `right` static clips.
    private func blendGraph(
        _ table: inout BehaviorObjectTable,
        firstWeight: Float,
        secondWeight: Float,
        threshold: Float = 0,
        flags: Int = 0,
        secondBinding: HKXPointerTarget? = nil
    ) -> (HKXPointerTarget, [HKXPointerTarget]) {
        let first = table.add(
            BehaviorFixture.clipGenerator("left", animationName: "left"), at: 0x100
        )
        let second = table.add(
            BehaviorFixture.clipGenerator("right", animationName: "right"), at: 0x110
        )
        let firstChild = table.add(
            BehaviorFixture.blenderChild(generator: first, weight: firstWeight), at: 0x120
        )
        let secondChild = table.add(
            BehaviorFixture.blenderChild(
                generator: second, weight: secondWeight, bindingSet: secondBinding
            ),
            at: 0x130
        )
        let root = table.add(
            BehaviorFixture.blender(
                "blend", children: [firstChild, secondChild], threshold: threshold, flags: flags
            ),
            at: 0x140
        )
        return (root, [firstChild, secondChild])
    }
}
