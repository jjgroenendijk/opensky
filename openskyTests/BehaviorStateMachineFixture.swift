// Synthetic state machines for the item 14.4 evaluator tests (issue #330).
//
// Same rule as `BehaviorFixture.swift`: everything here is invented and built
// in code, never an extracted file (AGENTS.md "Legal & IP boundary"). The
// shapes copy what the probe over the local install reports — a machine whose
// states point at clip generators, transitions keyed on event ids, a wildcard
// array on the machine, and `hkbBlendingTransitionEffect` crossfades — without
// carrying any of its data.

import Foundation
@testable import opensky

/// One transition of a synthetic machine.
struct BehaviorTransitionSpec {
    let eventId: Int
    let toStateId: Int
    var flags = BehaviorTransitionFlag.disableCondition
    var priority = 0
    var effect: HKXPointerTarget?
    var condition: HKXPointerTarget?
    var toNestedStateId = -1
    var triggerInterval = HKBStateMachineTimeInterval(
        enterEventId: -1, exitEventId: -1, enterTime: 0, exitTime: 0
    )
    var initiateInterval = HKBStateMachineTimeInterval(
        enterEventId: -1, exitEventId: -1, enterTime: 0, exitTime: 0
    )
}

/// One state of a synthetic machine.
struct BehaviorStateSpec {
    let stateId: Int
    let name: String
    var generator: HKXPointerTarget?
    var transitions: HKXPointerTarget?
    var enterNotifyEvents: HKXPointerTarget?
    var exitNotifyEvents: HKXPointerTarget?
    var probability: Float = 1
    var enable = true
}

enum BehaviorStateMachineFixture {
    // MARK: - States and transitions

    static func stateInfo(_ spec: BehaviorStateSpec) -> HKBStateMachineStateInfo {
        HKBStateMachineStateInfo(
            variableBindingSet: nil,
            enterNotifyEvents: spec.enterNotifyEvents,
            exitNotifyEvents: spec.exitNotifyEvents,
            transitions: spec.transitions,
            generator: spec.generator,
            name: spec.name,
            stateId: spec.stateId,
            probability: spec.probability,
            enable: spec.enable,
            unresolved: []
        )
    }

    static func transitions(_ specs: [BehaviorTransitionSpec])
        -> HKBStateMachineTransitionInfoArray
    {
        HKBStateMachineTransitionInfoArray(
            transitions: specs.map {
                HKBStateMachineTransitionInfo(
                    triggerInterval: $0.triggerInterval,
                    initiateInterval: $0.initiateInterval,
                    transition: $0.effect,
                    condition: $0.condition,
                    eventId: $0.eventId,
                    toStateId: $0.toStateId,
                    fromNestedStateId: -1,
                    toNestedStateId: $0.toNestedStateId,
                    priority: $0.priority,
                    flags: $0.flags
                )
            },
            unresolved: []
        )
    }

    static func notifyEvents(_ ids: [Int]) -> HKBStateMachineEventPropertyArray {
        HKBStateMachineEventPropertyArray(
            events: ids.map { HKBEventProperty(id: $0, payload: nil) },
            unresolved: []
        )
    }

    // MARK: - Machines

    static func machine(
        _ name: String,
        states: [HKXPointerTarget?],
        startStateId: Int = 0,
        startStateMode: Int = 0,
        syncVariableIndex: Int = -1,
        wildcardTransitions: HKXPointerTarget? = nil,
        changeEventId: Int = -1,
        returnToPreviousStateEventId: Int = -1,
        randomTransitionEventId: Int = -1,
        transitionToNextHigherStateEventId: Int = -1,
        transitionToNextLowerStateEventId: Int = -1,
        wrapAroundStateId: Bool = false,
        bindingSet: HKXPointerTarget? = nil
    ) -> HKBStateMachine {
        HKBStateMachine(
            node: BehaviorFixture.nodeHeader(name, bindingSet: bindingSet),
            eventToSendWhenStateOrTransitionChanges: HKBEventProperty(
                id: changeEventId, payload: nil
            ),
            startStateChooser: nil,
            startStateId: startStateId,
            returnToPreviousStateEventId: returnToPreviousStateEventId,
            randomTransitionEventId: randomTransitionEventId,
            transitionToNextHigherStateEventId: transitionToNextHigherStateEventId,
            transitionToNextLowerStateEventId: transitionToNextLowerStateEventId,
            syncVariableIndex: syncVariableIndex,
            wrapAroundStateId: wrapAroundStateId,
            maxSimultaneousTransitions: 32,
            startStateMode: startStateMode,
            selfTransitionMode: 0,
            states: states,
            wildcardTransitions: wildcardTransitions,
            unresolved: []
        )
    }

    // MARK: - Transition effects and conditions

    static func blendingEffect(
        duration: Float,
        blendCurve: Int = BehaviorBlendCurve.smooth,
        flags: Int = 0
    ) -> HKBBlendingTransitionEffect {
        HKBBlendingTransitionEffect(
            node: BehaviorFixture.nodeHeader("crossfade"),
            selfTransitionMode: 0,
            eventMode: 0,
            duration: duration,
            toGeneratorStartTimeFraction: 0,
            flags: flags,
            endMode: 0,
            blendCurve: blendCurve,
            unresolved: []
        )
    }

    static func condition(_ expression: String) -> HKBExpressionCondition {
        HKBExpressionCondition(expression: expression, unresolved: [])
    }

    // MARK: - Blenders

    /// A blender whose `m_indexOfSyncMasterChild` names one child, which is the
    /// authored signal that the other children follow its playback phase.
    static func syncedBlender(
        _ name: String,
        children: [HKXPointerTarget?],
        masterIndex: Int
    ) -> HKBBlenderGenerator {
        HKBBlenderGenerator(
            node: BehaviorFixture.nodeHeader(name),
            blender: HKBBlenderFields(
                referencePoseWeightThreshold: 0,
                blendParameter: 0,
                minCyclicBlendParameter: 0,
                maxCyclicBlendParameter: 0,
                indexOfSyncMasterChild: masterIndex,
                flags: 0,
                subtractLastChild: false,
                children: children
            ),
            unresolved: []
        )
    }
}
