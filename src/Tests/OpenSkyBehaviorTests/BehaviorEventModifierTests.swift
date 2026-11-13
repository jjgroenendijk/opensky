// `hkbEventDrivenModifier`, `BSEventEveryNEventsModifier`, and
// `BSRagdollContactListenerModifier` on a graph with no clips.

import Foundation
import OpenSkyBehavior
import OpenSkyEngineTesting
@testable import OpenSkyFormatsAnimation
import Testing

struct BehaviorEventModifierTests {
    private static let data = BehaviorFixture.graphData(events: ["Start", "Stop", "Hit"])

    private static func graph(root modifier: HKXPointerTarget, table: BehaviorObjectTable)
        -> BehaviorGraphInstance
    {
        var table = table
        let root = table.add(
            BehaviorFixture.modifierGenerator("root", modifier: modifier, generator: nil),
            at: 0x200
        )
        return BehaviorFixture.instance(root: root, table: table, data: data)
    }

    /// The wrapped listener runs only between the start and the stop events.
    @Test func anEventDrivenModifierRunsBetweenItsEvents() {
        var table = BehaviorObjectTable()
        let listener = table.add(BSRagdollContactListenerModifier(
            modifier: BehaviorFixture.modifierHeader("listen"),
            contactEvent: HKBEventProperty(id: 2, payload: nil), bones: nil, unresolved: []
        ), at: 0x100)
        let driven = table.add(HKBEventDrivenModifier(
            modifier: BehaviorFixture.modifierHeader("driven"), wrapped: listener,
            activateEventId: 0, deactivateEventId: 1, activeByDefault: false, unresolved: []
        ), at: 0x110)
        let graph = Self.graph(root: driven, table: table)
        _ = graph.update(deltaTime: 0.1)
        #expect(graph.physics.ragdollContactEvent == nil)
        _ = graph.raiseEvent(named: "Start")
        _ = graph.update(deltaTime: 0.1)
        #expect(graph.physics.ragdollContactEvent == "Hit")
    }

    /// Every second start event sends the hit event, also with a random count.
    @Test func anEventCounterSendsEveryNthEvent() {
        for randomize in [false, true] {
            var table = BehaviorObjectTable()
            let counter = table.add(BSEventEveryNEventsModifier(
                modifier: BehaviorFixture.modifierHeader("counter"),
                eventToCheckFor: HKBEventProperty(id: 0, payload: nil),
                eventToSend: HKBEventProperty(id: 2, payload: nil),
                numberOfEventsBeforeSend: 2, minimumNumberOfEventsBeforeSend: 2,
                randomizeNumberOfEvents: randomize, unresolved: []
            ), at: 0x100)
            let graph = Self.graph(root: counter, table: table)
            _ = graph.update(deltaTime: 0.1)
            for _ in 0 ..< 4 {
                _ = graph.raiseEvent(named: "Start")
                _ = graph.update(deltaTime: 0.1)
            }
            #expect(graph.isActive)
        }
    }

    /// The activate modifier of a modify-once runs on the first update.
    @Test func aModifyOnceRunsItsActivateModifierFirst() {
        var table = BehaviorObjectTable()
        let listener = table.add(BSRagdollContactListenerModifier(
            modifier: BehaviorFixture.modifierHeader("listen"),
            contactEvent: HKBEventProperty(id: 2, payload: nil), bones: nil, unresolved: []
        ), at: 0x100)
        let once = table.add(BSModifyOnceModifier(
            modifier: BehaviorFixture.modifierHeader("once"), onActivateModifier: listener,
            onDeactivateModifier: nil, unresolved: []
        ), at: 0x110)
        let graph = Self.graph(root: once, table: table)
        _ = graph.update(deltaTime: 0.1)
        #expect(graph.physics.ragdollContactEvent == "Hit")
        _ = graph.update(deltaTime: 0.1)
    }

    /// A damping modifier with both kinds on runs each update without a bound variable.
    @Test func aDampingModifierRunsWithoutBindings() {
        var table = BehaviorObjectTable()
        let damping = table.add(HKBDampingModifier(
            modifier: BehaviorFixture.modifierHeader("damp"), proportionalGain: 0.5,
            integralGain: 0.1, derivativeGain: 0.1, enableScalarDamping: true,
            enableVectorDamping: true, rawValue: 1, dampedValue: 0, rawVector: SIMD4(1, 0, 0, 0),
            dampedVector: .zero, vectorErrorSum: .zero, vectorPreviousError: .zero, errorSum: 0,
            previousError: 0, unresolved: []
        ), at: 0x100)
        let graph = Self.graph(root: damping, table: table)
        _ = graph.update(deltaTime: 0.1)
        _ = graph.update(deltaTime: 0.1)
        #expect(graph.isActive)
    }

    /// A slot raises its event when its bound flag turns true, once per change.
    @Test func aFalseToTrueSlotRaisesWhenItsFlagTurnsTrue() {
        var table = BehaviorObjectTable()
        let set = table.add(
            BehaviorFixture.bindingSet([BehaviorBindingSpec("bVariableToTest1", 0)]), at: 0x100
        )
        let slot = BSFalseToTrueSlot(
            enableEvent: true, variableToTest: false,
            eventToSend: HKBEventProperty(id: 2, payload: nil)
        )
        let modifier = table.add(BSEventOnFalseToTrueModifier(
            modifier: BehaviorFixture.modifierHeader("rising", bindingSet: set), slots: [slot],
            unresolved: []
        ), at: 0x110)
        let root = table.add(
            BehaviorFixture.modifierGenerator("root", modifier: modifier, generator: nil),
            at: 0x200
        )
        let graph = BehaviorFixture.instance(
            root: root, table: table,
            data: BehaviorFixture.graphData(
                variables: [BehaviorVariableSpec("Flag", .bool, 0)], events: [
                    "Start",
                    "Stop",
                    "Hit"
                ]
            )
        )
        _ = graph.update(deltaTime: 0.1)
        _ = graph.setVariable(.bool(true), named: "Flag")
        _ = graph.update(deltaTime: 0.1)
        #expect(graph.isActive)
    }

    /// A state manager whose machine never ran publishes nothing.
    @Test func aStateManagerSkipsAMachineThatNeverRan() {
        var table = BehaviorObjectTable()
        let manager = table.add(BSIStateManagerModifier(
            modifier: BehaviorFixture.modifierHeader("states"), iStateVar: 0,
            stateData: [BSIStateData(
                stateMachine: BehaviorFixture.target(0x400),
                stateID: 1,
                stateToSetAs: 2
            )],
            unresolved: []
        ), at: 0x100)
        let graph = Self.graph(root: manager, table: table)
        _ = graph.update(deltaTime: 0.1)
        #expect(graph.isActive)
    }

    /// A blender that subtracts its last child notes the gap and still blends.
    @Test func aSubtractingBlenderIsNoted() {
        var table = BehaviorObjectTable()
        let child = table.add(BehaviorFixture.blenderChild(generator: nil, weight: 1), at: 0x100)
        let root = table.add(HKBBlenderGenerator(
            node: BehaviorFixture.nodeHeader("blend"),
            blender: HKBBlenderFields(
                referencePoseWeightThreshold: 0, blendParameter: 0, minCyclicBlendParameter: 0,
                maxCyclicBlendParameter: 0, indexOfSyncMasterChild: -1, flags: 0,
                subtractLastChild: true, children: [child]
            ),
            unresolved: []
        ), at: 0x110)
        let graph = BehaviorFixture.instance(root: root, table: table)
        _ = graph.update(deltaTime: 0.1)
        #expect(graph.isActive)
    }
}
