// Bethesda's small utility modifiers: timers, vector splitting, the time step,
// the iState manager, the tweener, the pass-by trigger, and limb IK. All derive
// `hkbModifier`, so their own members start at 0x50.
// Byte map: docs/formats/hkx-behavior-modifiers.md.

import Foundation

/// Decoded `BSTimerModifier`, size 112: like `hkbTimerModifier`, with
/// `m_resetAlarm` to raise the alarm again every period.
nonisolated public struct BSTimerModifier: HKBClass, Equatable, Sendable {
    public let modifier: HKBModifierHeader
    public let alarmTimeSeconds: Float
    public let alarmEvent: HKBEventProperty
    public let resetAlarm: Bool
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "BSTimerModifier"

    private static let alarmTimeField = HKXField(0x50, "m_alarmTimeSeconds")
    private static let alarmEventOffset = 0x58
    private static let resetAlarmField = HKXField(0x68, "m_resetAlarm")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> BSTimerModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        let alarmTime = cursor.float32(at: alarmTimeField) ?? 0
        let event = HKBEventProperty.decode(&cursor, at: alarmEventOffset, named: "m_alarmEvent")
        return BSTimerModifier(
            modifier: header,
            alarmTimeSeconds: alarmTime,
            alarmEvent: event,
            resetAlarm: cursor.bool(at: resetAlarmField) ?? false,
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
        "alarm \(alarmTimeSeconds)s raises event \(alarmEvent.id), reset \(resetAlarm)"
    }
}

/// Decoded `BSDecomposeVectorModifier`, size 112: splits `m_vector` into the
/// four bound scalars `m_x` to `m_w`.
nonisolated public struct BSDecomposeVectorModifier: HKBClass, Equatable, Sendable {
    public let modifier: HKBModifierHeader
    public let vector: SIMD4<Float>
    public let components: SIMD4<Float>
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "BSDecomposeVectorModifier"

    private static let vectorField = HKXField(0x50, "m_vector")
    private static let componentFields = [
        HKXField(0x60, "m_x"), HKXField(0x64, "m_y"), HKXField(0x68, "m_z"), HKXField(0x6C, "m_w")
    ]

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> BSDecomposeVectorModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        let vector = cursor.vector4(at: vectorField) ?? SIMD4()
        var components = SIMD4<Float>()
        for (index, field) in componentFields.enumerated() {
            components[index] = cursor.float32(at: field) ?? 0
        }
        return BSDecomposeVectorModifier(
            modifier: header, vector: vector, components: components,
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
        "vector \(vector)"
    }
}

/// Decoded `BSGetTimeStepModifier`, size 96: publishes the update's time step
/// through its bound `m_timeStep`.
nonisolated public struct BSGetTimeStepModifier: HKBClass, Equatable, Sendable {
    public let modifier: HKBModifierHeader
    public let timeStep: Float
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "BSGetTimeStepModifier"

    private static let timeStepField = HKXField(0x50, "m_timeStep")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> BSGetTimeStepModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        return BSGetTimeStepModifier(
            modifier: header,
            timeStep: cursor.float32(at: timeStepField) ?? 0,
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
        "time step \(timeStep)"
    }
}

/// One `BSIStateManagerModifierBSiStateData`, 16 bytes: while the state machine
/// is in `stateID`, the manager publishes `stateToSetAs`.
nonisolated public struct BSIStateData: Equatable, Sendable {
    public let stateMachine: HKXPointerTarget?
    public let stateID: Int
    public let stateToSetAs: Int

    public static let stride = 16

    static func decode(_ element: inout HKXObjectCursor, index: Int) -> BSIStateData {
        let member = "m_stateData[\(index)]"
        return BSIStateData(
            stateMachine: element.pointer(at: HKXField(0x00, "\(member).m_pStateMachine")),
            stateID: element.int32(at: HKXField(0x08, "\(member).m_StateID")) ?? -1,
            stateToSetAs: element.int32(at: HKXField(0x0C, "\(member).m_iStateToSetAs")) ?? 0
        )
    }
}

/// Decoded `BSIStateManagerModifier`: writes the iState of whichever
/// listed state machine state is current into `m_iStateVar`.
nonisolated public struct BSIStateManagerModifier: HKBClass, Equatable, Sendable {
    public let modifier: HKBModifierHeader
    public let iStateVar: Int
    public let stateData: [BSIStateData]
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "BSIStateManagerModifier"

    private static let iStateVarField = HKXField(0x50, "m_iStateVar")
    private static let stateDataField = HKXField(0x58, "m_stateData")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> BSIStateManagerModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        let iStateVar = cursor.int32(at: iStateVarField) ?? 0
        let data = cursor.structArray(at: stateDataField, stride: BSIStateData.stride) {
            BSIStateData.decode(&$0, index: $1)
        }
        return BSIStateManagerModifier(
            modifier: header, iStateVar: iStateVar, stateData: data,
            unresolved: cursor.unresolved
        )
    }

    public var nodeName: String? {
        modifier.name
    }

    public var references: [HKBReference] {
        modifier.references + stateData.enumerated().flatMap { index, data in
            HKBReference.optional("m_stateData[\(index)].m_pStateMachine", data.stateMachine)
        }
    }

    public var summary: String {
        "\(stateData.count) states, iState \(iStateVar)"
    }
}

/// Decoded `BSTweenerModifier`, size 208: moves the character towards
/// `m_targetPosition` and `m_targetRotation` over a tween time.
nonisolated public struct BSTweenerModifier: HKBClass, Equatable, Sendable {
    public let modifier: HKBModifierHeader
    public let tweenPosition: Bool
    public let tweenRotation: Bool
    public let useTweenDuration: Bool
    public let tweenDuration: Float
    public let targetPosition: SIMD4<Float>
    /// `hkQuaternion` as (x, y, z, w).
    public let targetRotation: SIMD4<Float>
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "BSTweenerModifier"

    private static let tweenPositionField = HKXField(0x50, "m_tweenPosition")
    private static let tweenRotationField = HKXField(0x51, "m_tweenRotation")
    private static let useDurationField = HKXField(0x52, "m_useTweenDuration")
    private static let durationField = HKXField(0x54, "m_tweenDuration")
    private static let targetPositionField = HKXField(0x60, "m_targetPosition")
    private static let targetRotationField = HKXField(0x70, "m_targetRotation")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> BSTweenerModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        return BSTweenerModifier(
            modifier: header,
            tweenPosition: cursor.bool(at: tweenPositionField) ?? false,
            tweenRotation: cursor.bool(at: tweenRotationField) ?? false,
            useTweenDuration: cursor.bool(at: useDurationField) ?? false,
            tweenDuration: cursor.float32(at: durationField) ?? 0,
            targetPosition: cursor.vector4(at: targetPositionField) ?? SIMD4(),
            targetRotation: cursor.vector4(at: targetRotationField) ?? SIMD4(0, 0, 0, 1),
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
        "tween position \(tweenPosition), rotation \(tweenRotation) over \(tweenDuration)s"
    }
}

/// Decoded `BSPassByTargetTriggerModifier`, size 160: raises `m_triggerEvent`
/// once the character passes `m_targetPosition`.
nonisolated public struct BSPassByTargetTriggerModifier: HKBClass, Equatable, Sendable {
    public let modifier: HKBModifierHeader
    public let targetPosition: SIMD4<Float>
    public let radius: Float
    public let movementDirection: SIMD4<Float>
    public let triggerEvent: HKBEventProperty
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "BSPassByTargetTriggerModifier"

    private static let targetPositionField = HKXField(0x50, "m_targetPosition")
    private static let radiusField = HKXField(0x60, "m_radius")
    private static let movementDirectionField = HKXField(0x70, "m_movementDirection")
    private static let triggerEventOffset = 0x80

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> BSPassByTargetTriggerModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        let position = cursor.vector4(at: targetPositionField) ?? SIMD4()
        let radius = cursor.float32(at: radiusField) ?? 0
        let direction = cursor.vector4(at: movementDirectionField) ?? SIMD4()
        let event = HKBEventProperty.decode(
            &cursor, at: triggerEventOffset, named: "m_triggerEvent"
        )
        return BSPassByTargetTriggerModifier(
            modifier: header, targetPosition: position, radius: radius,
            movementDirection: direction, triggerEvent: event, unresolved: cursor.unresolved
        )
    }

    public var nodeName: String? {
        modifier.name
    }

    public var references: [HKBReference] {
        modifier.references + triggerEvent.references(named: "m_triggerEvent")
    }

    public var summary: String {
        "radius \(radius) raises event \(triggerEvent.id)"
    }
}

/// Decoded `BSLimbIKModifier`, size 128: bends the bone chain from
/// `m_startBoneIndex` to `m_endBoneIndex` away from geometry it would cut into.
nonisolated public struct BSLimbIKModifier: HKBClass, Equatable, Sendable {
    public let modifier: HKBModifierHeader
    public let limitAngleDegrees: Float
    public let startBoneIndex: Int
    public let endBoneIndex: Int
    public let gain: Float
    public let boneRadius: Float
    public let castOffset: Float
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "BSLimbIKModifier"

    private static let limitAngleField = HKXField(0x50, "m_limitAngleDegrees")
    private static let startBoneField = HKXField(0x58, "m_startBoneIndex")
    private static let endBoneField = HKXField(0x5A, "m_endBoneIndex")
    private static let gainField = HKXField(0x5C, "m_gain")
    private static let boneRadiusField = HKXField(0x60, "m_boneRadius")
    private static let castOffsetField = HKXField(0x64, "m_castOffset")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> BSLimbIKModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        return BSLimbIKModifier(
            modifier: header,
            limitAngleDegrees: cursor.float32(at: limitAngleField) ?? 0,
            startBoneIndex: cursor.int16(at: startBoneField) ?? -1,
            endBoneIndex: cursor.int16(at: endBoneField) ?? -1,
            gain: cursor.float32(at: gainField) ?? 0,
            boneRadius: cursor.float32(at: boneRadiusField) ?? 0,
            castOffset: cursor.float32(at: castOffsetField) ?? 0,
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
        "bones \(startBoneIndex)-\(endBoneIndex), limit \(limitAngleDegrees) deg"
    }
}
