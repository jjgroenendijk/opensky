// The `iState` tag a running `BSiStateTaggingGenerator` publishes, such as
// `MT_Drunk_iStateGen`.

import Foundation
import OpenSkyBehavior
import OpenSkyEngineTesting
@testable import OpenSkyFormatsAnimation
import Testing

struct BehaviorStateTagTests {
    private func tagging(
        _ name: String, child: HKXPointerTarget?, state: Int, priority: Int,
        bindingSet: HKXPointerTarget? = nil
    ) -> BSiStateTaggingGenerator {
        BSiStateTaggingGenerator(
            node: BehaviorFixture.nodeHeader(name, bindingSet: bindingSet),
            defaultGenerator: child, stateToSetAs: state, priority: priority, unresolved: []
        )
    }

    /// An outer tag around an inner tag around a clip.
    private func nestedGraph(
        outer: (state: Int, priority: Int), inner: (state: Int, priority: Int)
    ) -> BehaviorGraphInstance {
        var table = BehaviorObjectTable()
        let clip = table.add(
            BehaviorFixture.clipGenerator("clip", animationName: "left"), at: 0x100
        )
        let innerTag = table.add(
            tagging("inner", child: clip, state: inner.state, priority: inner.priority), at: 0x200
        )
        let root = table.add(
            tagging("outer", child: innerTag, state: outer.state, priority: outer.priority),
            at: 0x300
        )
        return BehaviorFixture.instance(
            root: root, table: table, clips: BehaviorFixture.staticClipPair(left: 0, right: 10)
        )
    }

    @Test func theHigherPriorityTagWins() {
        let graph = nestedGraph(outer: (3, 0), inner: (12, 5))
        #expect(graph.stateTag == nil)
        graph.update(deltaTime: 1 / 30)
        #expect(graph.stateTag == BehaviorStateTag(value: 12, priority: 5))

        let reversed = nestedGraph(outer: (3, 5), inner: (12, 0))
        reversed.update(deltaTime: 1 / 30)
        #expect(reversed.stateTag?.value == 3)
    }

    @Test func aTieKeepsTheFirstTagReached() {
        let graph = nestedGraph(outer: (3, 1), inner: (12, 1))
        graph.update(deltaTime: 1 / 30)
        #expect(graph.stateTag?.value == 3)
    }

    @Test func aBoundStateIsTaggedAndMatchesItsConstant() {
        var table = BehaviorObjectTable()
        let binding = table.add(
            BehaviorFixture.bindingSet([BehaviorBindingSpec("iStateToSetAs", 0)]), at: 0x50
        )
        let root = table.add(
            tagging("MT_Drunk_iStateGen", child: nil, state: 0, priority: 0, bindingSet: binding),
            at: 0x100
        )
        let data = BehaviorFixture.graphData(variables: [
            BehaviorVariableSpec("iState_NPCDrunk", .int32, 22),
            BehaviorVariableSpec("iState_NPCDefault", .int32, 0)
        ])
        let graph = BehaviorFixture.instance(root: root, table: table, data: data)
        #expect(!graph.isTaggingState("iState_NPCDrunk"))
        graph.update(deltaTime: 1 / 30)
        #expect(graph.stateTag?.value == 22)
        #expect(graph.isTaggingState("iState_NPCDrunk"))
        #expect(!graph.isTaggingState("iState_NPCDefault"))
        #expect(!graph.isTaggingState("iState_NPCSneaking"))
        graph.deactivate()
        #expect(graph.stateTag == nil)
    }
}
