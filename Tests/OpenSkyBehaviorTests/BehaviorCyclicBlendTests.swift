// `BSCyclicBlendTransitionGenerator`: the freeze event holds the blend parameter until
// the cross-blend event crossfades to the live blend.

import Foundation
import OpenSkyBehavior
import OpenSkyEngineTesting
@testable import OpenSkyFormatsAnimation
import simd
import Testing

struct BehaviorCyclicBlendTests {
    private static func graph() -> BehaviorGraphInstance {
        var table = BehaviorObjectTable()
        let left = table.add(
            BehaviorFixture.clipGenerator("left", animationName: "left"),
            at: 0x100
        )
        let right = table.add(
            BehaviorFixture.clipGenerator("right", animationName: "right"), at: 0x110
        )
        let leftChild = table.add(
            BehaviorFixture.blenderChild(generator: left, weight: 0),
            at: 0x120
        )
        let rightChild = table.add(
            BehaviorFixture.blenderChild(generator: right, weight: 1), at: 0x130
        )
        let blender = table.add(
            BehaviorFixture.blender(
                "blend", children: [leftChild, rightChild],
                flags: BehaviorBlenderFlag.parametricBlend
            ),
            at: 0x140
        )
        let binding = table.add(
            BehaviorFixture.bindingSet([BehaviorBindingSpec("fBlendParameter", 0)]), at: 0x50
        )
        let root = table.add(
            BSCyclicBlendTransitionGenerator(
                node: BehaviorFixture.nodeHeader("cyclic", bindingSet: binding),
                blenderGenerator: blender,
                eventToFreezeBlendValue: HKBEventProperty(id: 0, payload: nil),
                eventToCrossBlend: HKBEventProperty(id: 1, payload: nil),
                blendParameter: 0,
                transitionDuration: 0.2,
                blendCurve: BehaviorBlendCurve.linear,
                unresolved: []
            ),
            at: 0x150
        )
        return BehaviorFixture.instance(
            root: root,
            table: table,
            data: BehaviorFixture.graphData(
                variables: [BehaviorVariableSpec("Direction", .real, 0.2)],
                events: ["Freeze", "Cross"]
            ),
            clips: BehaviorFixture.staticClipPair(left: 0, right: 10)
        )
    }

    private static func x(_ graph: BehaviorGraphInstance) -> Float {
        graph.update(deltaTime: 0.1).bones[1].translation.x
    }

    @Test func freezeHoldsTheParameterUntilTheCrossBlendFadesToTheLiveBlend() {
        let graph = Self.graph()
        #expect(abs(Self.x(graph) - 2) < 1e-4)
        let froze = graph.raiseEvent(named: "Freeze")
        #expect(froze)
        _ = Self.x(graph)
        graph.setVariable(.real(0.8), named: "Direction")
        #expect(abs(Self.x(graph) - 2) < 1e-4)
        let crossed = graph.raiseEvent(named: "Cross")
        #expect(crossed)
        // Halfway through a linear 0.2 s crossfade from 2 to the live 8.
        #expect(abs(Self.x(graph) - 5) < 1e-4)
        #expect(abs(Self.x(graph) - 8) < 1e-4)
    }

    @Test func aRepeatedCrossBlendMirrorsTheProgress() {
        let graph = Self.graph()
        _ = Self.x(graph)
        _ = graph.raiseEvent(named: "Freeze")
        _ = Self.x(graph)
        graph.setVariable(.real(0.8), named: "Direction")
        _ = graph.raiseEvent(named: "Cross")
        // 0.1 of 0.2 s from 2 to 8.
        #expect(abs(Self.x(graph) - 5) < 1e-4)
        _ = graph.raiseEvent(named: "Cross")
        // The repeat sets elapsed to 0.2 - 0.1, and this step adds 0.1: the fade ends.
        #expect(abs(Self.x(graph) - 8) < 1e-4)
    }

    @Test func theTwoNewBlendCurvesEaseAtOneEndOnly() {
        #expect(abs(BehaviorBlendCurve.weight(0.5, curve: 2) - 0.625) < 1e-6)
        #expect(abs(BehaviorBlendCurve.weight(0.5, curve: 3) - 0.375) < 1e-6)
        #expect(BehaviorBlendCurve.weight(1, curve: 2) == 1)
        #expect(BehaviorBlendCurve.weight(1, curve: 3) == 1)
    }
}
