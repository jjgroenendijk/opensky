// `hkbStateMachine` and `hkbStateMachineStateInfo`: the class most of the node
// tree is made of. Transition arrays are separate objects, decoded in
// HKBStateMachineTransitions.swift.
// Byte map and citations: docs/formats/hkx-behavior-nodes.md.

import Foundation

/// Decoded `hkbStateMachine`, size 264. Derives `hkbGenerator` -> `hkbNode`, so
/// the inherited members occupy 0x10 through 0x47 and its own start at 0x48.
nonisolated public struct HKBStateMachine: HKBClass, Equatable, Sendable {
    public let node: HKBNodeHeader
    /// Raised whenever the machine changes state or starts a transition.
    public let eventToSendWhenStateOrTransitionChanges: HKBEventProperty
    /// Optional `hkbStateChooser` that overrides the start state at activation.
    /// No vanilla player file carries one, so this is normally null.
    public let startStateChooser: HKXPointerTarget?
    /// State *id* (not index) the machine enters when activated.
    public let startStateId: Int
    public let returnToPreviousStateEventId: Int
    public let randomTransitionEventId: Int
    public let transitionToNextHigherStateEventId: Int
    public let transitionToNextLowerStateEventId: Int
    /// Index of the graph variable this machine keeps its current state in, or
    /// -1 when the machine is not variable-synced.
    public let syncVariableIndex: Int
    public let wrapAroundStateId: Bool
    public let maxSimultaneousTransitions: Int
    /// `hkbStateMachine::StartStateMode`: 0 uses `m_startStateId`, 1 syncs from
    /// the variable, 2 re-enters the state that was current at deactivation.
    public let startStateMode: Int
    /// `hkbStateMachine::StateMachineSelfTransitionMode`.
    public let selfTransitionMode: Int
    /// `hkbStateMachineStateInfo` objects, index-preserving.
    public let states: [HKXPointerTarget?]
    /// `hkbStateMachineTransitionInfoArray` of transitions that may fire from
    /// any state.
    public let wildcardTransitions: HKXPointerTarget?
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbStateMachine"

    private static let eventToSendField = 0x48
    private static let startStateChooserField = HKXField(0x60, "m_startStateChooser")
    private static let startStateIdField = HKXField(0x68, "m_startStateId")
    private static let returnToPreviousStateEventIdField = HKXField(
        0x6C, "m_returnToPreviousStateEventId"
    )
    private static let randomTransitionEventIdField = HKXField(
        0x70, "m_randomTransitionEventId"
    )
    private static let transitionToNextHigherStateEventIdField = HKXField(
        0x74, "m_transitionToNextHigherStateEventId"
    )
    private static let transitionToNextLowerStateEventIdField = HKXField(
        0x78, "m_transitionToNextLowerStateEventId"
    )
    private static let syncVariableIndexField = HKXField(0x7C, "m_syncVariableIndex")
    // 0x80 is m_currentStateId, SERIALIZE_IGNORED, which is why the authored
    // flags resume at 0x84 rather than 0x80.
    private static let wrapAroundStateIdField = HKXField(0x84, "m_wrapAroundStateId")
    private static let maxSimultaneousTransitionsField = HKXField(
        0x85, "m_maxSimultaneousTransitions"
    )
    private static let startStateModeField = HKXField(0x86, "m_startStateMode")
    private static let selfTransitionModeField = HKXField(0x87, "m_selfTransitionMode")
    private static let statesField = HKXField(0x90, "m_states")
    private static let wildcardTransitionsField = HKXField(0xA0, "m_wildcardTransitions")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBStateMachine?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let node = HKBNodeHeader.decode(&cursor)
        let changeEvent = HKBEventProperty.decode(
            &cursor,
            at: eventToSendField,
            named: "m_eventToSendWhenStateOrTransitionChanges"
        )
        return HKBStateMachine(
            node: node,
            eventToSendWhenStateOrTransitionChanges: changeEvent,
            startStateChooser: cursor.pointer(at: startStateChooserField),
            startStateId: cursor.int32(at: startStateIdField) ?? -1,
            returnToPreviousStateEventId: cursor
                .int32(at: returnToPreviousStateEventIdField) ?? -1,
            randomTransitionEventId: cursor.int32(at: randomTransitionEventIdField) ?? -1,
            transitionToNextHigherStateEventId: cursor
                .int32(at: transitionToNextHigherStateEventIdField) ?? -1,
            transitionToNextLowerStateEventId: cursor
                .int32(at: transitionToNextLowerStateEventIdField) ?? -1,
            syncVariableIndex: cursor.int32(at: syncVariableIndexField) ?? -1,
            wrapAroundStateId: cursor.bool(at: wrapAroundStateIdField) ?? false,
            maxSimultaneousTransitions: cursor
                .int8(at: maxSimultaneousTransitionsField) ?? 0,
            startStateMode: cursor.int8(at: startStateModeField) ?? 0,
            selfTransitionMode: cursor.int8(at: selfTransitionModeField) ?? 0,
            states: cursor.pointerArray(at: statesField),
            wildcardTransitions: cursor.pointer(at: wildcardTransitionsField),
            unresolved: cursor.unresolved
        )
    }

    public var nodeName: String? {
        node.name
    }

    public var references: [HKBReference] {
        node.references
            + eventToSendWhenStateOrTransitionChanges
            .references(named: "m_eventToSendWhenStateOrTransitionChanges")
            + HKBReference.optional("m_startStateChooser", startStateChooser)
            + HKBReference.each("m_states", states)
            + HKBReference.optional("m_wildcardTransitions", wildcardTransitions)
    }

    public var summary: String {
        "\(states.count) states, start state id \(startStateId), "
            + "start mode \(startStateMode), sync variable \(syncVariableIndex)"
    }
}

/// Decoded `hkbStateMachineStateInfo`, size 120. Derives `hkbBindable`, not
/// `hkbNode`, so it has a name of its own at 0x60 rather than the inherited one
/// at 0x38 — the most common offset mistake in this class set.
nonisolated public struct HKBStateMachineStateInfo: HKBClass, Equatable, Sendable {
    public let variableBindingSet: HKXPointerTarget?
    /// `hkbStateMachineEventPropertyArray` raised on entering this state.
    public let enterNotifyEvents: HKXPointerTarget?
    /// `hkbStateMachineEventPropertyArray` raised on leaving it.
    public let exitNotifyEvents: HKXPointerTarget?
    /// `hkbStateMachineTransitionInfoArray` of transitions out of this state.
    public let transitions: HKXPointerTarget?
    /// The generator that runs while this state is current.
    public let generator: HKXPointerTarget?
    public let name: String?
    /// The id transitions address this state by; not its index in `m_states`.
    public let stateId: Int
    /// Weight when a random transition picks among candidate states.
    public let probability: Float
    public let enable: Bool
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbStateMachineStateInfo"

    private static let variableBindingSetField = HKXField(0x10, "m_variableBindingSet")
    private static let enterNotifyEventsField = HKXField(0x40, "m_enterNotifyEvents")
    private static let exitNotifyEventsField = HKXField(0x48, "m_exitNotifyEvents")
    private static let transitionsField = HKXField(0x50, "m_transitions")
    private static let generatorField = HKXField(0x58, "m_generator")
    private static let nameField = HKXField(0x60, "m_name")
    private static let stateIdField = HKXField(0x68, "m_stateId")
    private static let probabilityField = HKXField(0x6C, "m_probability")
    private static let enableField = HKXField(0x70, "m_enable")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBStateMachineStateInfo?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        return HKBStateMachineStateInfo(
            variableBindingSet: cursor.pointer(at: variableBindingSetField),
            enterNotifyEvents: cursor.pointer(at: enterNotifyEventsField),
            exitNotifyEvents: cursor.pointer(at: exitNotifyEventsField),
            transitions: cursor.pointer(at: transitionsField),
            generator: cursor.pointer(at: generatorField),
            name: cursor.string(at: nameField),
            stateId: cursor.int32(at: stateIdField) ?? -1,
            probability: cursor.float32(at: probabilityField) ?? 0,
            enable: cursor.bool(at: enableField) ?? false,
            unresolved: cursor.unresolved
        )
    }

    public var nodeName: String? {
        name
    }

    public var references: [HKBReference] {
        HKBReference.optional("m_variableBindingSet", variableBindingSet)
            + HKBReference.optional("m_enterNotifyEvents", enterNotifyEvents)
            + HKBReference.optional("m_exitNotifyEvents", exitNotifyEvents)
            + HKBReference.optional("m_transitions", transitions)
            + HKBReference.optional("m_generator", generator)
    }

    public var summary: String {
        "state id \(stateId), probability \(probability), enable \(enable)"
    }
}
