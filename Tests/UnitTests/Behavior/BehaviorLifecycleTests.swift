// Node lifecycle and determinism of the behavior evaluator (issue #187): what
// activation and deactivation do, and the promise that two instances stepped
// the same way produce the same poses and the same event log. Synthetic graphs
// built in code (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import simd
import Testing

struct BehaviorLifecycleTests {
    // MARK: - Lifecycle

    @Test func aNodeNoLongerReachedIsDeactivatedAndFiresItsDeactivateEvent() {
        let data = BehaviorFixture.graphData(
            variables: [BehaviorVariableSpec("iSelect", .int32, 0)], events: ["leftStopped"]
        )
        var table = BehaviorObjectTable()
        let clip = table.add(
            BehaviorFixture.clipGenerator("left", animationName: "left"), at: 0x100
        )
        let onDeactivate = table.add(
            BSEventOnDeactivateModifier(
                modifier: BehaviorFixture.modifierHeader("stopper"),
                event: HKBEventProperty(id: 0, payload: nil),
                unresolved: []
            ),
            at: 0x110
        )
        let wrapped = table.add(
            BehaviorFixture.modifierGenerator(
                "left+stopper", modifier: onDeactivate, generator: clip
            ),
            at: 0x120
        )
        let other = table.add(
            BehaviorFixture.clipGenerator("right", animationName: "right"), at: 0x130
        )
        let binding = table.add(
            BehaviorFixture.bindingSet([BehaviorBindingSpec("m_selectedGeneratorIndex", 0)]),
            at: 0x140
        )
        let root = table.add(
            BehaviorFixture.selector(
                "select", generators: [wrapped, other], bindingSet: binding
            ),
            at: 0x150
        )
        let graph = BehaviorFixture.instance(
            root: root,
            table: table,
            data: data,
            clips: BehaviorFixture.staticClipPair(left: 1, right: 2)
        )

        #expect(graph.update(deltaTime: 1 / 30).firedEvents.isEmpty)
        graph.setVariable(.int(1), named: "iSelect")
        // The deactivation happens at the end of this update, so its event is
        // visible to the one after it.
        #expect(graph.update(deltaTime: 1 / 30).firedEvents.isEmpty)
        #expect(
            graph.update(deltaTime: 1 / 30).firedEvents.map(\.name) == ["leftStopped"]
        )
    }

    @Test func deactivatingTheInstanceDropsEveryNodeState() {
        var table = BehaviorObjectTable()
        let root = table.add(
            BehaviorFixture.clipGenerator("clip", animationName: "left"), at: 0x100
        )
        let graph = BehaviorFixture.instance(
            root: root,
            table: table,
            data: BehaviorFixture.graphData(),
            clips: BehaviorFixture.staticClipPair(left: 1, right: 2)
        )
        graph.update(deltaTime: 0.5)
        #expect(!graph.nodeStates.isEmpty)
        graph.deactivate()
        #expect(graph.nodeStates.isEmpty)
        #expect(!graph.isActive)
    }

    // MARK: - Determinism

    @Test func twoInstancesSteppedIdenticallyProduceIdenticalOutput() throws {
        let clip = try BehaviorFixture.splineClip()
        let data = BehaviorFixture.graphData(
            variables: [BehaviorVariableSpec("iSelect", .int32, 0)], events: ["mark"]
        )
        var table = BehaviorObjectTable()
        let triggers = table.add(
            BehaviorFixture.clipTriggers(
                [BehaviorTriggerSpec(
                    localTime: 0.4,
                    eventId: 0,
                    relativeToEnd: false,
                    acyclic: false
                )]
            ),
            at: 0x100
        )
        let root = table.add(
            BehaviorFixture.clipGenerator(
                "walk", animationName: "walk", triggers: triggers
            ),
            at: 0x200
        )
        let clips = BehaviorClipTable(byName: ["walk": clip])

        func run() -> ([[HKABonePose]], [[String?]]) {
            let graph = BehaviorFixture.instance(root: root, table: table, data: data, clips: clips)
            var poses: [[HKABonePose]] = []
            var events: [[String?]] = []
            for step in 0 ..< 40 {
                if step == 10 {
                    graph.setVariable(.int(1), named: "iSelect")
                }
                let result = graph.update(deltaTime: 1 / 30)
                poses.append(result.bones)
                events.append(result.firedEvents.map(\.name))
            }
            return (poses, events)
        }

        let (firstPoses, firstEvents) = run()
        let (secondPoses, secondEvents) = run()
        #expect(firstPoses == secondPoses)
        #expect(firstEvents == secondEvents)
        #expect(firstEvents.contains { $0 == ["mark"] })
    }
}
