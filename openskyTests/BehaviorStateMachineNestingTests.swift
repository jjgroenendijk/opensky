// Nested machines, clip synchronization, and determinism across both
// (issue #330). Synthetic graphs built in code, nothing from the install.

import Foundation
@testable import opensky
import Testing

struct BehaviorStateMachineNestingTests {
    private static let step: Float = 0.1
    private static let events = ["go", "outerEnter", "outerExit", "innerEnter", "innerExit"]

    /// Outer machine: state 0 "Outer_Idle" runs a clip, state 1 "Outer_Move"
    /// runs a nested machine whose two states run clips of their own. The
    /// nested machine's states carry their own notify events, so the order the
    /// two machines report entering and leaving is observable.
    private struct NestedGraph {
        var table = BehaviorObjectTable()
        var root: HKXPointerTarget?

        init(nestedStartStateId: Int = 0, toNestedStateId: Int = -1) {
            let idle = table.add(
                BehaviorFixture.clipGenerator("idle", animationName: "left"), at: 0x100
            )
            let inner = addInnerMachine(startStateId: nestedStartStateId)
            var flags = BehaviorTransitionFlag.disableCondition
            if toNestedStateId >= 0 {
                flags |= BehaviorTransitionFlag.toNestedStateIsValid
            }
            let outerTransitions = table.add(
                BehaviorStateMachineFixture.transitions([
                    BehaviorTransitionSpec(
                        eventId: 0, toStateId: 1, flags: flags,
                        toNestedStateId: toNestedStateId
                    )
                ]),
                at: 0x500
            )
            let outerEnter = table.add(
                BehaviorStateMachineFixture.notifyEvents([1]), at: 0x510
            )
            let outerExit = table.add(
                BehaviorStateMachineFixture.notifyEvents([2]), at: 0x520
            )
            let idleState = table.add(
                BehaviorStateMachineFixture.stateInfo(
                    BehaviorStateSpec(
                        stateId: 0, name: "Outer_Idle", generator: idle,
                        transitions: outerTransitions, exitNotifyEvents: outerExit
                    )
                ),
                at: 0x600
            )
            let moveState = table.add(
                BehaviorStateMachineFixture.stateInfo(
                    BehaviorStateSpec(
                        stateId: 1, name: "Outer_Move", generator: inner,
                        enterNotifyEvents: outerEnter
                    )
                ),
                at: 0x610
            )
            root = table.add(
                BehaviorStateMachineFixture.machine(
                    "outer", states: [idleState, moveState]
                ),
                at: 0x700
            )
        }

        /// The machine nested under the outer machine's second state: two
        /// states, each running a clip, the first carrying notify events of its
        /// own so the order the two machines report is observable.
        private mutating func addInnerMachine(startStateId: Int) -> HKXPointerTarget {
            let walk = table.add(
                BehaviorFixture.clipGenerator("walk", animationName: "right"), at: 0x110
            )
            let run = table.add(
                BehaviorFixture.clipGenerator("run", animationName: "far"), at: 0x120
            )
            let innerEnter = table.add(
                BehaviorStateMachineFixture.notifyEvents([3]), at: 0x200
            )
            let innerExit = table.add(
                BehaviorStateMachineFixture.notifyEvents([4]), at: 0x210
            )
            let walkState = table.add(
                BehaviorStateMachineFixture.stateInfo(
                    BehaviorStateSpec(
                        stateId: 0, name: "Inner_Walk", generator: walk,
                        enterNotifyEvents: innerEnter, exitNotifyEvents: innerExit
                    )
                ),
                at: 0x300
            )
            let runState = table.add(
                BehaviorStateMachineFixture.stateInfo(
                    BehaviorStateSpec(stateId: 1, name: "Inner_Run", generator: run)
                ),
                at: 0x310
            )
            return table.add(
                BehaviorStateMachineFixture.machine(
                    "inner", states: [walkState, runState], startStateId: startStateId
                ),
                at: 0x400
            )
        }

        func instance() -> BehaviorGraphInstance {
            BehaviorFixture.instance(
                root: root,
                table: table,
                data: BehaviorFixture.graphData(events: BehaviorStateMachineNestingTests.events),
                clips: BehaviorClipTable(byName: [
                    "left": BehaviorStaticClip(samples: [BehaviorFixture.sample(bone: 1, x: 0)]),
                    "right": BehaviorStaticClip(samples: [BehaviorFixture.sample(bone: 1, x: 10)]),
                    "far": BehaviorStaticClip(samples: [BehaviorFixture.sample(bone: 1, x: 20)])
                ])
            )
        }
    }

    // MARK: - Nesting

    @Test func aNestedMachineRunsItsOwnStartState() {
        let graph = NestedGraph().instance()
        graph.update(deltaTime: Self.step)
        graph.raiseEvent(named: "go")
        #expect(graph.update(deltaTime: Self.step).bones[1].translation.x == 10)
        #expect(graph.activeStates.map(\.stateName) == ["Outer_Move", "Inner_Walk"])
    }

    /// The outer machine reports before the machine nested under it, because
    /// the walk reaches it first, and both are entered in that order.
    @Test func enterEventsRunOuterBeforeInner() {
        let graph = NestedGraph().instance()
        graph.update(deltaTime: Self.step)
        graph.raiseEvent(named: "go")
        graph.update(deltaTime: Self.step)
        let fired = graph.update(deltaTime: Self.step).firedEvents.map(\.name)
        #expect(fired == ["outerExit", "outerEnter", "innerEnter"])
    }

    /// Leaving the outer state deactivates the nested machine, which raises the
    /// exit events of whatever state it was in.
    @Test func deactivationRaisesTheNestedStatesExitEvents() {
        let graph = NestedGraph().instance()
        graph.update(deltaTime: Self.step)
        graph.raiseEvent(named: "go")
        graph.update(deltaTime: Self.step)
        graph.update(deltaTime: Self.step)
        graph.deactivate()
        #expect(graph.update(deltaTime: Self.step).firedEvents.map(\.name).contains("innerExit"))
    }

    /// `FLAG_TO_NESTED_STATE_ID_IS_VALID` puts the nested machine into the state
    /// the transition names rather than into its own start state.
    @Test func aTransitionCanNameTheNestedStartState() {
        let graph = NestedGraph(toNestedStateId: 1).instance()
        graph.update(deltaTime: Self.step)
        graph.raiseEvent(named: "go")
        #expect(graph.update(deltaTime: Self.step).bones[1].translation.x == 20)
        #expect(graph.activeStates.map(\.stateName) == ["Outer_Move", "Inner_Run"])
    }

    // MARK: - Determinism

    /// The #187 determinism test extended to a nested graph driven through a
    /// transition: two instances over the same decoded objects, stepped with
    /// the same events, produce the same poses and the same event log.
    @Test func twoNestedInstancesStepIdentically() {
        let fixture = NestedGraph()
        let first = fixture.instance()
        let second = fixture.instance()
        var firstLog: [String] = []
        var secondLog: [String] = []
        for index in 0 ..< 12 {
            if index == 3 {
                first.raiseEvent(named: "go")
                second.raiseEvent(named: "go")
            }
            let left = first.update(deltaTime: Self.step)
            let right = second.update(deltaTime: Self.step)
            #expect(left.bones == right.bones)
            #expect(first.activeStates == second.activeStates)
            firstLog += left.firedEvents.compactMap(\.name)
            secondLog += right.firedEvents.compactMap(\.name)
        }
        #expect(firstLog == secondLog)
        #expect(firstLog.contains("innerEnter"))
    }

    // MARK: - Clip synchronization

    /// A blender whose `m_indexOfSyncMasterChild` names child 0 holds child 1
    /// at the same phase, so two loops of different lengths stay in step: after
    /// 0.6 s the 2 s master sits at phase 0.3 and the 4 s follower at 1.2 s.
    @Test func aSyncMasterHoldsItsSiblingsAtItsOwnPhase() throws {
        var table = BehaviorObjectTable()
        let fast = table.add(
            BehaviorFixture.clipGenerator("fast", animationName: "fast"), at: 0x100
        )
        let slow = table.add(
            BehaviorFixture.clipGenerator("slow", animationName: "slow"), at: 0x110
        )
        let fastChild = table.add(
            BehaviorFixture.blenderChild(generator: fast, weight: 1), at: 0x200
        )
        let slowChild = table.add(
            BehaviorFixture.blenderChild(generator: slow, weight: 1), at: 0x210
        )
        let root = table.add(
            BehaviorStateMachineFixture.syncedBlender(
                "locomotion", children: [fastChild, slowChild], masterIndex: 0
            ),
            at: 0x300
        )
        let graph = BehaviorFixture.instance(
            root: root,
            table: table,
            clips: BehaviorClipTable(byName: [
                "fast": BehaviorRampClip(duration: 2, boneIndex: 1, rate: 1),
                "slow": BehaviorRampClip(duration: 4, boneIndex: 1, rate: 1)
            ])
        )
        for _ in 0 ..< 6 {
            graph.update(deltaTime: Self.step)
        }
        let master = try #require(graph.nodeStates[fast])
        let follower = try #require(graph.nodeStates[slow])
        #expect(master.phase == follower.phase)
        #expect(abs(master.localTime - 0.6) < 1e-5)
        #expect(abs(follower.localTime - 1.2) < 1e-5)
    }
}
