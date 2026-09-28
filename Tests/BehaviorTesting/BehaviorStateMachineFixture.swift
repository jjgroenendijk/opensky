// Synthetic state machines for the item 14.4 evaluator tests (issue #330).
//
// Same rule as `BehaviorFixture.swift`: everything here is invented and built
// in code, never an extracted file (AGENTS.md "Legal & IP boundary"). The
// shapes copy what the probe over the local install reports — a machine whose
// states point at clip generators, transitions keyed on event ids, a wildcard
// array on the machine, and `hkbBlendingTransitionEffect` crossfades — without
// carrying any of its data.

import Foundation
@testable import OpenSkyBehavior
@testable import OpenSkyFormatsAnimation

/// One transition of a synthetic machine.
public struct BehaviorTransitionSpec: Sendable {
    public let eventId: Int
    public let toStateId: Int
    public var flags = BehaviorTransitionFlag.disableCondition
    public var priority = 0
    public var effect: HKXPointerTarget?
    public var condition: HKXPointerTarget?
    public var toNestedStateId = -1
    public var triggerInterval = HKBStateMachineTimeInterval(
        enterEventId: -1, exitEventId: -1, enterTime: 0, exitTime: 0
    )
    public var initiateInterval = HKBStateMachineTimeInterval(
        enterEventId: -1, exitEventId: -1, enterTime: 0, exitTime: 0
    )

    public init(
        eventId: Int,
        toStateId: Int,
        flags: Int = BehaviorTransitionFlag.disableCondition,
        priority: Int = 0,
        effect: HKXPointerTarget? = nil,
        condition: HKXPointerTarget? = nil,
        toNestedStateId: Int = -1,
        triggerInterval: HKBStateMachineTimeInterval = HKBStateMachineTimeInterval(
            enterEventId: -1, exitEventId: -1, enterTime: 0, exitTime: 0
        ),
        initiateInterval: HKBStateMachineTimeInterval = HKBStateMachineTimeInterval(
            enterEventId: -1, exitEventId: -1, enterTime: 0, exitTime: 0
        )
    ) {
        self.eventId = eventId
        self.toStateId = toStateId
        self.flags = flags
        self.priority = priority
        self.effect = effect
        self.condition = condition
        self.toNestedStateId = toNestedStateId
        self.triggerInterval = triggerInterval
        self.initiateInterval = initiateInterval
    }
}

/// One state of a synthetic machine.
public struct BehaviorStateSpec: Sendable {
    public let stateId: Int
    public let name: String
    public var generator: HKXPointerTarget?
    public var transitions: HKXPointerTarget?
    public var enterNotifyEvents: HKXPointerTarget?
    public var exitNotifyEvents: HKXPointerTarget?
    public var probability: Float = 1
    public var enable = true

    public init(
        stateId: Int,
        name: String,
        generator: HKXPointerTarget? = nil,
        transitions: HKXPointerTarget? = nil,
        enterNotifyEvents: HKXPointerTarget? = nil,
        exitNotifyEvents: HKXPointerTarget? = nil,
        probability: Float = 1,
        enable: Bool = true
    ) {
        self.stateId = stateId
        self.name = name
        self.generator = generator
        self.transitions = transitions
        self.enterNotifyEvents = enterNotifyEvents
        self.exitNotifyEvents = exitNotifyEvents
        self.probability = probability
        self.enable = enable
    }
}

public enum BehaviorStateMachineFixture {
    // MARK: - States and transitions

    public static func stateInfo(_ spec: BehaviorStateSpec) -> HKBStateMachineStateInfo {
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

    public static func transitions(_ specs: [BehaviorTransitionSpec])
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

    public static func notifyEvents(_ ids: [Int]) -> HKBStateMachineEventPropertyArray {
        HKBStateMachineEventPropertyArray(
            events: ids.map { HKBEventProperty(id: $0, payload: nil) },
            unresolved: []
        )
    }

    // MARK: - Machines

    public static func machine(
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

    public static func blendingEffect(
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

    public static func condition(_ expression: String) -> HKBExpressionCondition {
        HKBExpressionCondition(expression: expression, unresolved: [])
    }

    // MARK: - Blenders

    /// A blender whose `m_indexOfSyncMasterChild` names one child, which is the
    /// authored signal that the other children follow its playback phase.
    public static func syncedBlender(
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
