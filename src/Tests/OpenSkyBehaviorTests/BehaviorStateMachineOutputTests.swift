// What a state machine publishes: `isActive` and `currentStateId` through output
// bindings, and its current state through its sync variable. The machine sits under a
// selector, so switching the selector deactivates it.

import Foundation
@testable import OpenSkyBehavior
import OpenSkyEngineTesting
@testable import OpenSkyFormatsAnimation
import Testing

struct BehaviorStateMachineOutputTests {
    private static let step: Float = 0.1

    /// Variables: 0 `iSelect`, 1 `bActive`, 2 `iCurrent`, 3 `iSync`.
    private static func graph() -> BehaviorGraphInstance {
        var table = BehaviorObjectTable()
        let left = table.add(
            BehaviorFixture.clipGenerator("left", animationName: "left"), at: 0x100
        )
        let right = table.add(
            BehaviorFixture.clipGenerator("right", animationName: "right"), at: 0x110
        )
        let toRight = table.add(
            BehaviorStateMachineFixture.transitions([
                BehaviorTransitionSpec(eventId: 0, toStateId: 1)
            ]),
            at: 0x200
        )
        let leftState = table.add(
            BehaviorStateMachineFixture.stateInfo(
                BehaviorStateSpec(stateId: 0, name: "Left", generator: left, transitions: toRight)
            ),
            at: 0x300
        )
        let rightState = table.add(
            BehaviorStateMachineFixture.stateInfo(
                BehaviorStateSpec(stateId: 1, name: "Right", generator: right)
            ),
            at: 0x310
        )
        let machineSet = table.add(
            BehaviorFixture.bindingSet([
                BehaviorBindingSpec("m_isActive", 1), BehaviorBindingSpec("m_currentStateId", 2)
            ]),
            at: 0x400
        )
        let machine = table.add(
            BehaviorStateMachineFixture.machine(
                "machine", states: [leftState, rightState], syncVariableIndex: 3,
                bindingSet: machineSet
            ),
            at: 0x410
        )
        let root = selector(over: machine, in: &table)
        return BehaviorFixture.instance(
            root: root, table: table,
            data: BehaviorFixture.graphData(
                variables: [
                    BehaviorVariableSpec("iSelect", .int32, 0),
                    BehaviorVariableSpec("bActive", .bool, 0),
                    BehaviorVariableSpec("iCurrent", .int32, 0),
                    BehaviorVariableSpec("iSync", .int32, 0)
                ],
                events: ["go"]
            ),
            clips: BehaviorFixture.staticClipPair(left: 0, right: 10)
        )
    }

    /// A selector bound to variable 0 that picks the machine or a plain clip.
    private static func selector(
        over machine: HKXPointerTarget, in table: inout BehaviorObjectTable
    ) -> HKXPointerTarget {
        let other = table.add(
            BehaviorFixture.clipGenerator("other", animationName: "left"), at: 0x500
        )
        let selectSet = table.add(
            BehaviorFixture.bindingSet([BehaviorBindingSpec("m_selectedGeneratorIndex", 0)]),
            at: 0x510
        )
        return table.add(
            BehaviorFixture.selector("select", generators: [machine, other], bindingSet: selectSet),
            at: 0x520
        )
    }

    @Test func aRunningMachinePublishesItsStateAndActivity() {
        let graph = Self.graph()
        graph.update(deltaTime: Self.step)
        #expect(graph.variable(named: "bActive") == .bool(true))
        #expect(graph.variable(named: "iCurrent") == .int(0))
        #expect(graph.variable(named: "iSync") == .int(0))

        graph.raiseEvent(named: "go")
        graph.update(deltaTime: Self.step)
        #expect(graph.variable(named: "iCurrent") == .int(1))
        #expect(graph.variable(named: "iSync") == .int(1))
    }

    @Test func aMachineThatStopsRunningReadsInactive() {
        let graph = Self.graph()
        graph.update(deltaTime: Self.step)
        graph.setVariable(.int(1), named: "iSelect")
        graph.update(deltaTime: Self.step)
        graph.update(deltaTime: Self.step)
        #expect(graph.variable(named: "bActive") == .bool(false))
    }
}
