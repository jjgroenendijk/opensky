// The two array classes an `hkbStateMachine` state points at (todo 14.2):
// `hkbStateMachineTransitionInfoArray`, which holds the transitions out of a
// state (or the wildcard transitions of the machine), and
// `hkbStateMachineEventPropertyArray`, which holds the events a state raises on
// entry and on exit. Both are thin `hkReferencedObject` wrappers around one
// hkArray of inline structs, which is why the structs carry the interesting
// layout and the classes almost none.
//
// 64-bit member offsets from ret2end/HKX2Library (MIT); signatures match the
// local SSE files (hkbStateMachineTransitionInfoArray 0xE397B11E,
// hkbStateMachineEventPropertyArray 0xB07B4388, hkbStateMachineTransitionInfo
// 0xCDEC8025, hkbStateMachineTimeInterval 0x60A881E5). Byte map and citations:
// docs/formats/hkx-behavior-nodes.md.

import Foundation

/// Decoded `hkbStateMachineTimeInterval`, 16 bytes: the window, in local time
/// or between two events, during which a transition may trigger or initiate.
nonisolated struct HKBStateMachineTimeInterval: Equatable {
    let enterEventId: Int
    let exitEventId: Int
    let enterTime: Float
    let exitTime: Float

    static let stride = 16

    static func decode(
        _ cursor: inout HKXObjectCursor,
        at offset: Int,
        named member: String
    ) -> HKBStateMachineTimeInterval {
        HKBStateMachineTimeInterval(
            enterEventId: cursor
                .int32(at: HKXField(offset + 0x00, "\(member).m_enterEventId")) ?? -1,
            exitEventId: cursor
                .int32(at: HKXField(offset + 0x04, "\(member).m_exitEventId")) ?? -1,
            enterTime: cursor
                .float32(at: HKXField(offset + 0x08, "\(member).m_enterTime")) ?? 0,
            exitTime: cursor
                .float32(at: HKXField(offset + 0x0C, "\(member).m_exitTime")) ?? 0
        )
    }
}

/// One entry of `hkbStateMachineTransitionInfoArray::m_transitions`, 72 bytes.
nonisolated struct HKBStateMachineTransitionInfo: Equatable {
    let triggerInterval: HKBStateMachineTimeInterval
    let initiateInterval: HKBStateMachineTimeInterval
    /// The `hkbTransitionEffect` that blends between the two generators; null
    /// means an instant cut.
    let transition: HKXPointerTarget?
    /// An `hkbCondition` that must hold for the transition to fire.
    let condition: HKXPointerTarget?
    /// Index into the graph's event list that triggers this transition.
    let eventId: Int
    /// `hkbStateMachineStateInfo::m_stateId` of the destination state.
    let toStateId: Int
    let fromNestedStateId: Int
    let toNestedStateId: Int
    let priority: Int
    /// `hkbStateMachineTransitionInfo::TransitionFlags`.
    let flags: Int

    static let stride = 72

    private static let transitionField = HKXField(0x20, "m_transition")
    private static let conditionField = HKXField(0x28, "m_condition")
    private static let eventIdField = HKXField(0x30, "m_eventId")
    private static let toStateIdField = HKXField(0x34, "m_toStateId")
    private static let fromNestedStateIdField = HKXField(0x38, "m_fromNestedStateId")
    private static let toNestedStateIdField = HKXField(0x3C, "m_toNestedStateId")
    private static let priorityField = HKXField(0x40, "m_priority")
    private static let flagsField = HKXField(0x42, "m_flags")

    static func decode(_ element: inout HKXObjectCursor) -> HKBStateMachineTransitionInfo {
        HKBStateMachineTransitionInfo(
            triggerInterval: HKBStateMachineTimeInterval.decode(
                &element, at: 0x00, named: "m_triggerInterval"
            ),
            initiateInterval: HKBStateMachineTimeInterval.decode(
                &element, at: 0x10, named: "m_initiateInterval"
            ),
            transition: element.pointer(at: transitionField),
            condition: element.pointer(at: conditionField),
            eventId: element.int32(at: eventIdField) ?? -1,
            toStateId: element.int32(at: toStateIdField) ?? -1,
            fromNestedStateId: element.int32(at: fromNestedStateIdField) ?? -1,
            toNestedStateId: element.int32(at: toNestedStateIdField) ?? -1,
            priority: element.int16(at: priorityField) ?? 0,
            flags: element.int16(at: flagsField) ?? 0
        )
    }

    func references(index: Int) -> [HKBReference] {
        HKBReference.optional("m_transitions[\(index)].m_transition", transition)
            + HKBReference.optional("m_transitions[\(index)].m_condition", condition)
    }
}

/// Decoded `hkbStateMachineTransitionInfoArray`, size 32.
nonisolated struct HKBStateMachineTransitionInfoArray: HKBClass, Equatable {
    let transitions: [HKBStateMachineTransitionInfo]
    let unresolved: [HKXUnresolvedReference]

    static let className = "hkbStateMachineTransitionInfoArray"

    private static let transitionsField = HKXField(0x10, "m_transitions")

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBStateMachineTransitionInfoArray?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        var transitions: [HKBStateMachineTransitionInfo] = []
        if let view = cursor.array(at: transitionsField) {
            transitions.reserveCapacity(view.count)
            for index in 0 ..< view.count {
                guard
                    var element = graph.element(
                        of: view,
                        index: index,
                        stride: HKBStateMachineTransitionInfo.stride
                    )
                else {
                    cursor.recordMiss(transitionsField, .outOfBounds)
                    continue
                }
                transitions.append(HKBStateMachineTransitionInfo.decode(&element))
                cursor.absorb(element)
            }
        }
        return HKBStateMachineTransitionInfoArray(
            transitions: transitions, unresolved: cursor.unresolved
        )
    }

    var references: [HKBReference] {
        transitions.enumerated().flatMap { $1.references(index: $0) }
    }

    var summary: String {
        "\(transitions.count) transitions"
    }
}

/// Decoded `hkbStateMachineEventPropertyArray`, size 32: the events a state
/// raises when it is entered or left.
nonisolated struct HKBStateMachineEventPropertyArray: HKBClass, Equatable {
    let events: [HKBEventProperty]
    let unresolved: [HKXUnresolvedReference]

    static let className = "hkbStateMachineEventPropertyArray"

    private static let eventsField = HKXField(0x10, "m_events")

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBStateMachineEventPropertyArray?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        var events: [HKBEventProperty] = []
        if let view = cursor.array(at: eventsField) {
            events.reserveCapacity(view.count)
            for index in 0 ..< view.count {
                guard
                    var element = graph.element(
                        of: view, index: index, stride: HKBEventProperty.stride
                    )
                else {
                    cursor.recordMiss(eventsField, .outOfBounds)
                    continue
                }
                events.append(HKBEventProperty.decode(
                    &element, at: 0x00, named: "m_events[\(index)]"
                ))
                cursor.absorb(element)
            }
        }
        return HKBStateMachineEventPropertyArray(
            events: events, unresolved: cursor.unresolved
        )
    }

    var references: [HKBReference] {
        events.enumerated().flatMap { index, event in
            event.references(named: "m_events[\(index)]")
        }
    }

    var summary: String {
        "\(events.count) events: " + events.map { String($0.id) }.joined(separator: ", ")
    }
}
