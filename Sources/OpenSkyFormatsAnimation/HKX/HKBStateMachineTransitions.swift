// The transition array and the event property array a state machine state
// points at. Both wrap one hkArray of inline structs. Offsets from HKX2Library
// (MIT). Byte map: docs/formats/hkx-behavior-nodes.md.

import Foundation

/// Decoded `hkbStateMachineTimeInterval`, 16 bytes: the window, in local time
/// or between two events, during which a transition may trigger or initiate.
nonisolated public struct HKBStateMachineTimeInterval: Equatable, Sendable {
    public let enterEventId: Int
    public let exitEventId: Int
    public let enterTime: Float
    public let exitTime: Float

    public static func decode(
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
nonisolated public struct HKBStateMachineTransitionInfo: Equatable, Sendable {
    public let triggerInterval: HKBStateMachineTimeInterval
    public let initiateInterval: HKBStateMachineTimeInterval
    /// The `hkbTransitionEffect` that blends between the two generators; null
    /// means an instant cut.
    public let transition: HKXPointerTarget?
    /// An `hkbCondition` that must hold for the transition to fire.
    public let condition: HKXPointerTarget?
    /// Index into the graph's event list that triggers this transition.
    public let eventId: Int
    /// `hkbStateMachineStateInfo::m_stateId` of the destination state.
    public let toStateId: Int
    public let fromNestedStateId: Int
    public let toNestedStateId: Int
    public let priority: Int
    /// `hkbStateMachineTransitionInfo::TransitionFlags`.
    public let flags: Int

    public static let stride = 72

    private static let transitionField = HKXField(0x20, "m_transition")
    private static let conditionField = HKXField(0x28, "m_condition")
    private static let eventIdField = HKXField(0x30, "m_eventId")
    private static let toStateIdField = HKXField(0x34, "m_toStateId")
    private static let fromNestedStateIdField = HKXField(0x38, "m_fromNestedStateId")
    private static let toNestedStateIdField = HKXField(0x3C, "m_toNestedStateId")
    private static let priorityField = HKXField(0x40, "m_priority")
    private static let flagsField = HKXField(0x42, "m_flags")

    public static func decode(_ element: inout HKXObjectCursor) -> HKBStateMachineTransitionInfo {
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

    public func references(index: Int) -> [HKBReference] {
        HKBReference.optional("m_transitions[\(index)].m_transition", transition)
            + HKBReference.optional("m_transitions[\(index)].m_condition", condition)
    }
}

/// Decoded `hkbStateMachineTransitionInfoArray`, size 32.
nonisolated public struct HKBStateMachineTransitionInfoArray: HKBClass, Equatable, Sendable {
    public let transitions: [HKBStateMachineTransitionInfo]
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbStateMachineTransitionInfoArray"

    private static let transitionsField = HKXField(0x10, "m_transitions")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
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

    public var references: [HKBReference] {
        transitions.enumerated().flatMap { $1.references(index: $0) }
    }

    public var summary: String {
        "\(transitions.count) transitions"
    }
}

/// Decoded `hkbStateMachineEventPropertyArray`, size 32: the events a state
/// raises when it is entered or left.
nonisolated public struct HKBStateMachineEventPropertyArray: HKBClass, Equatable, Sendable {
    public let events: [HKBEventProperty]
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbStateMachineEventPropertyArray"

    private static let eventsField = HKXField(0x10, "m_events")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
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

    public var references: [HKBReference] {
        events.enumerated().flatMap { index, event in
            event.references(named: "m_events[\(index)]")
        }
    }

    public var summary: String {
        "\(events.count) events: " + events.map { String($0.id) }.joined(separator: ", ")
    }
}
