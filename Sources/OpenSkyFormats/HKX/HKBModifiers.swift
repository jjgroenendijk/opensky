// The stock Havok modifier classes the vanilla player graph uses (todo 14.2),
// part one: the modifiers that wrap or list other modifiers, evaluate
// expressions, raise events, and damp values. A modifier is a node that runs
// after a generator and edits the pose, the graph variables, or the event
// queue; every one of them derives `hkbModifier` -> `hkbNode`, so
// `m_enable` at 0x48 is the last inherited member and each class's own start
// at 0x50.
//
// Decode only. Which modifier does what to a pose is item 14.3 and 14.4.
//
// 64-bit member offsets from ret2end/HKX2Library (MIT); signatures match the
// local SSE files (hkbModifierList 0xA4180CA1, hkbEventDrivenModifier
// 0x7ED3F44E, hkbEvaluateExpressionModifier 0xF900F6BE,
// hkbEventsFromRangeModifier 0xBC561B6E, hkbTimerModifier 0x338B4879,
// hkbDampingModifier 0x9A040F03). Byte map: docs/formats/hkx-behavior-modifiers.md.

import Foundation

/// Decoded `hkbModifierList`, size 96: runs a list of modifiers in order.
nonisolated public struct HKBModifierList: HKBClass, Equatable, Sendable {
    public let modifier: HKBModifierHeader
    public let modifiers: [HKXPointerTarget?]
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbModifierList"

    private static let modifiersField = HKXField(0x50, "m_modifiers")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBModifierList?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        return HKBModifierList(
            modifier: header,
            modifiers: cursor.pointerArray(at: modifiersField),
            unresolved: cursor.unresolved
        )
    }

    public var nodeName: String? {
        modifier.name
    }

    public var references: [HKBReference] {
        modifier.references + HKBReference.each("m_modifiers", modifiers)
    }

    public var summary: String {
        "\(modifiers.count) modifiers, enable \(modifier.enable)"
    }
}

/// Decoded `hkbEventDrivenModifier`, size 104. Derives `hkbModifierWrapper`,
/// which contributes the wrapped `m_modifier` pointer at 0x50, so this class's
/// own members start at 0x58.
nonisolated public struct HKBEventDrivenModifier: HKBClass, Equatable, Sendable {
    public let modifier: HKBModifierHeader
    /// The wrapped modifier, run only while this one is active.
    public let wrapped: HKXPointerTarget?
    public let activateEventId: Int
    public let deactivateEventId: Int
    public let activeByDefault: Bool
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbEventDrivenModifier"

    private static let wrappedField = HKXField(0x50, "m_modifier")
    private static let activateField = HKXField(0x58, "m_activateEventId")
    private static let deactivateField = HKXField(0x5C, "m_deactivateEventId")
    private static let activeByDefaultField = HKXField(0x60, "m_activeByDefault")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBEventDrivenModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        return HKBEventDrivenModifier(
            modifier: header,
            wrapped: cursor.pointer(at: wrappedField),
            activateEventId: cursor.int32(at: activateField) ?? -1,
            deactivateEventId: cursor.int32(at: deactivateField) ?? -1,
            activeByDefault: cursor.bool(at: activeByDefaultField) ?? false,
            unresolved: cursor.unresolved
        )
    }

    public var nodeName: String? {
        modifier.name
    }

    public var references: [HKBReference] {
        modifier.references + HKBReference.optional("m_modifier", wrapped)
    }

    public var summary: String {
        "activate on event \(activateEventId), deactivate on \(deactivateEventId)"
    }
}

/// Decoded `hkbEvaluateExpressionModifier`, size 112: evaluates a list of
/// expressions each frame and assigns their results to variables or events.
nonisolated public struct HKBEvaluateExpressionModifier: HKBClass, Equatable, Sendable {
    public let modifier: HKBModifierHeader
    /// `hkbExpressionDataArray` holding the expressions.
    public let expressions: HKXPointerTarget?
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbEvaluateExpressionModifier"

    private static let expressionsField = HKXField(0x50, "m_expressions")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBEvaluateExpressionModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        return HKBEvaluateExpressionModifier(
            modifier: header,
            expressions: cursor.pointer(at: expressionsField),
            unresolved: cursor.unresolved
        )
    }

    public var nodeName: String? {
        modifier.name
    }

    public var references: [HKBReference] {
        modifier.references + HKBReference.optional("m_expressions", expressions)
    }

    public var summary: String {
        "expressions \(expressions != nil ? "set" : "none"), enable \(modifier.enable)"
    }
}

/// Decoded `hkbEventsFromRangeModifier`, size 112: raises events depending on
/// which band of a numeric range an input value falls into.
nonisolated public struct HKBEventsFromRangeModifier: HKBClass, Equatable, Sendable {
    public let modifier: HKBModifierHeader
    /// The value tested; normally bound to a graph variable.
    public let inputValue: Float
    /// Lower edge of the first band; each `hkbEventRangeData` supplies an
    /// upper edge and the bands chain from there.
    public let lowerBound: Float
    /// `hkbEventRangeDataArray` of bands.
    public let eventRanges: HKXPointerTarget?
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbEventsFromRangeModifier"

    private static let inputValueField = HKXField(0x50, "m_inputValue")
    private static let lowerBoundField = HKXField(0x54, "m_lowerBound")
    private static let eventRangesField = HKXField(0x58, "m_eventRanges")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBEventsFromRangeModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        return HKBEventsFromRangeModifier(
            modifier: header,
            inputValue: cursor.float32(at: inputValueField) ?? 0,
            lowerBound: cursor.float32(at: lowerBoundField) ?? 0,
            eventRanges: cursor.pointer(at: eventRangesField),
            unresolved: cursor.unresolved
        )
    }

    public var nodeName: String? {
        modifier.name
    }

    public var references: [HKBReference] {
        modifier.references + HKBReference.optional("m_eventRanges", eventRanges)
    }

    public var summary: String {
        "input \(inputValue), lower bound \(lowerBound)"
    }
}

/// Decoded `hkbTimerModifier`, size 112: raises one event once its alarm time
/// has elapsed since activation.
nonisolated public struct HKBTimerModifier: HKBClass, Equatable, Sendable {
    public let modifier: HKBModifierHeader
    public let alarmTimeSeconds: Float
    public let alarmEvent: HKBEventProperty
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbTimerModifier"

    private static let alarmTimeField = HKXField(0x50, "m_alarmTimeSeconds")
    private static let alarmEventOffset = 0x58

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBTimerModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        let alarmTime = cursor.float32(at: alarmTimeField) ?? 0
        return HKBTimerModifier(
            modifier: header,
            alarmTimeSeconds: alarmTime,
            alarmEvent: HKBEventProperty.decode(
                &cursor, at: alarmEventOffset, named: "m_alarmEvent"
            ),
            unresolved: cursor.unresolved
        )
    }

    public var nodeName: String? {
        modifier.name
    }

    public var references: [HKBReference] {
        modifier.references + alarmEvent.references(named: "m_alarmEvent")
    }

    public var summary: String {
        "alarm \(alarmTimeSeconds)s raises event \(alarmEvent.id)"
    }
}

/// Decoded `hkbDampingModifier`, size 192: a PID filter that smooths a scalar
/// or a vector, so a variable a binding writes each frame does not jump.
nonisolated public struct HKBDampingModifier: HKBClass, Equatable, Sendable {
    public let modifier: HKBModifierHeader
    public let proportionalGain: Float
    public let integralGain: Float
    public let derivativeGain: Float
    public let enableScalarDamping: Bool
    public let enableVectorDamping: Bool
    public let rawValue: Float
    public let dampedValue: Float
    public let rawVector: SIMD4<Float>
    public let dampedVector: SIMD4<Float>
    public let vectorErrorSum: SIMD4<Float>
    public let vectorPreviousError: SIMD4<Float>
    public let errorSum: Float
    public let previousError: Float
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbDampingModifier"

    // Havok spells these m_kP, m_kI, and m_kD; the Swift names are spelled out
    // because a two-letter member trips the identifier-name lint rule.
    private static let proportionalGainField = HKXField(0x50, "m_kP")
    private static let integralGainField = HKXField(0x54, "m_kI")
    private static let derivativeGainField = HKXField(0x58, "m_kD")
    private static let enableScalarField = HKXField(0x5C, "m_enableScalarDamping")
    private static let enableVectorField = HKXField(0x5D, "m_enableVectorDamping")
    private static let rawValueField = HKXField(0x60, "m_rawValue")
    private static let dampedValueField = HKXField(0x64, "m_dampedValue")
    private static let rawVectorField = HKXField(0x70, "m_rawVector")
    private static let dampedVectorField = HKXField(0x80, "m_dampedVector")
    private static let vectorErrorSumField = HKXField(0x90, "m_vecErrorSum")
    private static let vectorPreviousErrorField = HKXField(0xA0, "m_vecPreviousError")
    private static let errorSumField = HKXField(0xB0, "m_errorSum")
    private static let previousErrorField = HKXField(0xB4, "m_previousError")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBDampingModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        return HKBDampingModifier(
            modifier: header,
            proportionalGain: cursor.float32(at: proportionalGainField) ?? 0,
            integralGain: cursor.float32(at: integralGainField) ?? 0,
            derivativeGain: cursor.float32(at: derivativeGainField) ?? 0,
            enableScalarDamping: cursor.bool(at: enableScalarField) ?? false,
            enableVectorDamping: cursor.bool(at: enableVectorField) ?? false,
            rawValue: cursor.float32(at: rawValueField) ?? 0,
            dampedValue: cursor.float32(at: dampedValueField) ?? 0,
            rawVector: cursor.vector4(at: rawVectorField) ?? SIMD4(),
            dampedVector: cursor.vector4(at: dampedVectorField) ?? SIMD4(),
            vectorErrorSum: cursor.vector4(at: vectorErrorSumField) ?? SIMD4(),
            vectorPreviousError: cursor.vector4(at: vectorPreviousErrorField) ?? SIMD4(),
            errorSum: cursor.float32(at: errorSumField) ?? 0,
            previousError: cursor.float32(at: previousErrorField) ?? 0,
            unresolved: cursor.unresolved
        )
    }

    public var nodeName: String? {
        modifier.name
    }

    public var references: [HKBReference] {
        modifier.references
    }

    public var summary: String {
        "gains \(proportionalGain)/\(integralGain)/\(derivativeGain), "
            + "scalar \(enableScalarDamping), vector \(enableVectorDamping)"
    }
}
