// The condition and expression classes (todo 14.2). A state-machine transition
// may name an `hkbCondition`; the vanilla player graph uses two,
// `hkbExpressionCondition` and `hkbStringCondition`, both of which carry their
// test as authored text rather than as compiled bytecode — the compiled form is
// a `SERIALIZE_IGNORED` member Havok rebuilds at load.
//
// That text is the graph's little expression language ("Speed > 0.1",
// "iState == 3"). Parsing and evaluating it is item 14.3; this decodes the
// string and the variable and event indices it is assigned to.
//
// 64-bit member offsets from ret2end/HKX2Library (MIT); signatures match the
// local SSE files (hkbExpressionCondition 0x1C3C1045, hkbStringCondition
// 0x5AB50487, hkbExpressionDataArray 0x4B9EE1A2, hkbEventRangeDataArray
// 0x330A56EE). Byte map: docs/formats/hkx-behavior-nodes.md.

import Foundation

/// Decoded `hkbExpressionCondition`, size 32. Derives `hkbCondition`, which
/// adds nothing to `hkReferencedObject`, so the expression sits at 0x10.
nonisolated struct HKBExpressionCondition: HKBClass, Equatable {
    /// The authored test, e.g. `bIsSynced == 1`.
    let expression: String?
    let unresolved: [HKXUnresolvedReference]

    static let className = "hkbExpressionCondition"

    private static let expressionField = HKXField(0x10, "m_expression")

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBExpressionCondition?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        return HKBExpressionCondition(
            expression: cursor.string(at: expressionField),
            unresolved: cursor.unresolved
        )
    }

    var summary: String {
        "condition \"\(expression ?? "")\""
    }
}

/// Decoded `hkbStringCondition`, size 24: the same idea with the member spelled
/// `m_conditionString`.
nonisolated struct HKBStringCondition: HKBClass, Equatable {
    let conditionString: String?
    let unresolved: [HKXUnresolvedReference]

    static let className = "hkbStringCondition"

    private static let conditionStringField = HKXField(0x10, "m_conditionString")

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBStringCondition?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        return HKBStringCondition(
            conditionString: cursor.string(at: conditionStringField),
            unresolved: cursor.unresolved
        )
    }

    var summary: String {
        "condition \"\(conditionString ?? "")\""
    }
}

/// One entry of `hkbExpressionDataArray::m_expressionsData`, 24 bytes: an
/// expression plus where its result goes.
nonisolated struct HKBExpressionData: Equatable {
    let expression: String?
    /// Graph variable the result is written to, or -1.
    let assignmentVariableIndex: Int
    /// Event raised when the expression becomes true, or -1.
    let assignmentEventIndex: Int
    /// `hkbEvaluateExpressionModifier::EventMode`: 0 raise on true, 1 raise on
    /// false-to-true, 2 raise on true-to-false.
    let eventMode: Int

    static let stride = 24

    static func decode(_ element: inout HKXObjectCursor, index: Int) -> HKBExpressionData {
        let member = "m_expressionsData[\(index)]"
        return HKBExpressionData(
            expression: element.string(at: HKXField(0x00, "\(member).m_expression")),
            assignmentVariableIndex: element
                .int32(at: HKXField(0x08, "\(member).m_assignmentVariableIndex")) ?? -1,
            assignmentEventIndex: element
                .int32(at: HKXField(0x0C, "\(member).m_assignmentEventIndex")) ?? -1,
            eventMode: element.int8(at: HKXField(0x10, "\(member).m_eventMode")) ?? 0
        )
    }
}

/// Decoded `hkbExpressionDataArray`, size 32.
nonisolated struct HKBExpressionDataArray: HKBClass, Equatable {
    let expressionsData: [HKBExpressionData]
    let unresolved: [HKXUnresolvedReference]

    static let className = "hkbExpressionDataArray"

    private static let expressionsDataField = HKXField(0x10, "m_expressionsData")

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBExpressionDataArray?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        var entries: [HKBExpressionData] = []
        if let view = cursor.array(at: expressionsDataField) {
            entries.reserveCapacity(view.count)
            for index in 0 ..< view.count {
                guard
                    var element = graph.element(
                        of: view, index: index, stride: HKBExpressionData.stride
                    )
                else {
                    cursor.recordMiss(expressionsDataField, .outOfBounds)
                    continue
                }
                entries.append(HKBExpressionData.decode(&element, index: index))
                cursor.absorb(element)
            }
        }
        return HKBExpressionDataArray(
            expressionsData: entries, unresolved: cursor.unresolved
        )
    }

    var summary: String {
        "\(expressionsData.count) expressions"
    }
}

/// One entry of `hkbEventRangeDataArray::m_eventData`, 32 bytes: the event to
/// raise while an input value sits below `m_upperBound`.
nonisolated struct HKBEventRangeData: Equatable {
    let upperBound: Float
    let event: HKBEventProperty
    /// `hkbEventRangeData::EventRangeMode`: 0 send on entering the range,
    /// 1 send on exiting it, 2 send while inside it.
    let eventMode: Int

    static let stride = 32

    static func decode(_ element: inout HKXObjectCursor, index: Int) -> HKBEventRangeData {
        let member = "m_eventData[\(index)]"
        return HKBEventRangeData(
            upperBound: element
                .float32(at: HKXField(0x00, "\(member).m_upperBound")) ?? 0,
            event: HKBEventProperty.decode(&element, at: 0x08, named: "\(member).m_event"),
            eventMode: element.int8(at: HKXField(0x18, "\(member).m_eventMode")) ?? 0
        )
    }
}

/// Decoded `hkbEventRangeDataArray`, size 32.
nonisolated struct HKBEventRangeDataArray: HKBClass, Equatable {
    let eventData: [HKBEventRangeData]
    let unresolved: [HKXUnresolvedReference]

    static let className = "hkbEventRangeDataArray"

    private static let eventDataField = HKXField(0x10, "m_eventData")

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBEventRangeDataArray?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        var entries: [HKBEventRangeData] = []
        if let view = cursor.array(at: eventDataField) {
            entries.reserveCapacity(view.count)
            for index in 0 ..< view.count {
                guard
                    var element = graph.element(
                        of: view, index: index, stride: HKBEventRangeData.stride
                    )
                else {
                    cursor.recordMiss(eventDataField, .outOfBounds)
                    continue
                }
                entries.append(HKBEventRangeData.decode(&element, index: index))
                cursor.absorb(element)
            }
        }
        return HKBEventRangeDataArray(eventData: entries, unresolved: cursor.unresolved)
    }

    var references: [HKBReference] {
        eventData.enumerated().flatMap { index, entry in
            entry.event.references(named: "m_eventData[\(index)].m_event")
        }
    }

    var summary: String {
        "\(eventData.count) event ranges"
    }
}
