// The stock Havok modifier classes the vanilla player graph uses (todo 14.2),
// part two: the ones that edit bones directly rather than variables or events —
// twist, character rotation, bone keyframing, get-up alignment — and the three
// ragdoll and foot-IK control modifiers.
//
// The ragdoll classes are decoded because the full-graph rule says a census
// class gets a decoder; what they mean is physics, which the milestone scope
// puts in M15. Their nested `hkaKeyFrameHierarchyUtilityControlData` block is
// physics tuning of that kind, so this decoder reads the members the behavior
// graph itself addresses and records the nested block as reserved rather than
// guessing at a class it cannot yet verify — flagged in the docs.
//
// 64-bit member offsets from ret2end/HKX2Library (MIT); signatures match the
// local SSE files (hkbTwistModifier 0xB6B76B32, hkbRotateCharacterModifier
// 0x877EBC0B, hkbKeyframeBonesModifier 0x95F66629, hkbGetUpModifier 0x61CB7AC0,
// hkbFootIkControlsModifier 0xE5B6F544, hkbPoweredRagdollControlsModifier
// 0x7CB54065, hkbRigidBodyRagdollControlsModifier 0xAA87D1EB). Byte map:
// docs/formats/hkx-behavior-nodes.md.

import Foundation

/// Decoded `hkbTwistModifier`, size 144: spreads one rotation across a chain of
/// bones, which is how the player's spine follows the aim direction.
nonisolated struct HKBTwistModifier: HKBClass, Equatable {
    let modifier: HKBModifierHeader
    let axisOfRotation: SIMD4<Float>
    let twistAngle: Float
    let startBoneIndex: Int
    let endBoneIndex: Int
    /// `hkbTwistModifier::SetAngleMethod`: 0 linear, 1 ramped.
    let setAngleMethod: Int
    /// `hkbTwistModifier::RotationAxisCoordinates`: 0 model space, 1 local.
    let rotationAxisCoordinates: Int
    let isAdditive: Bool
    let unresolved: [HKXUnresolvedReference]

    static let className = "hkbTwistModifier"

    private static let axisField = HKXField(0x50, "m_axisOfRotation")
    private static let twistAngleField = HKXField(0x60, "m_twistAngle")
    private static let startBoneField = HKXField(0x64, "m_startBoneIndex")
    private static let endBoneField = HKXField(0x66, "m_endBoneIndex")
    private static let setAngleMethodField = HKXField(0x68, "m_setAngleMethod")
    private static let axisCoordinatesField = HKXField(0x69, "m_rotationAxisCoordinates")
    private static let isAdditiveField = HKXField(0x6A, "m_isAdditive")

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBTwistModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        return HKBTwistModifier(
            modifier: header,
            axisOfRotation: cursor.vector4(at: axisField) ?? SIMD4(),
            twistAngle: cursor.float32(at: twistAngleField) ?? 0,
            startBoneIndex: cursor.int16(at: startBoneField) ?? -1,
            endBoneIndex: cursor.int16(at: endBoneField) ?? -1,
            setAngleMethod: cursor.int8(at: setAngleMethodField) ?? 0,
            rotationAxisCoordinates: cursor.int8(at: axisCoordinatesField) ?? 0,
            isAdditive: cursor.bool(at: isAdditiveField) ?? false,
            unresolved: cursor.unresolved
        )
    }

    var nodeName: String? {
        modifier.name
    }

    var references: [HKBReference] {
        modifier.references
    }

    var summary: String {
        "twist \(twistAngle) rad over bones \(startBoneIndex)-\(endBoneIndex)"
    }
}

/// Decoded `hkbRotateCharacterModifier`, size 128: turns the whole character at
/// a fixed rate, used by the turn-in-place states.
nonisolated struct HKBRotateCharacterModifier: HKBClass, Equatable {
    let modifier: HKBModifierHeader
    let degreesPerSecond: Float
    let speedMultiplier: Float
    let axisOfRotation: SIMD4<Float>
    let unresolved: [HKXUnresolvedReference]

    static let className = "hkbRotateCharacterModifier"

    private static let degreesPerSecondField = HKXField(0x50, "m_degreesPerSecond")
    private static let speedMultiplierField = HKXField(0x54, "m_speedMultiplier")
    private static let axisField = HKXField(0x60, "m_axisOfRotation")

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBRotateCharacterModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        return HKBRotateCharacterModifier(
            modifier: header,
            degreesPerSecond: cursor.float32(at: degreesPerSecondField) ?? 0,
            speedMultiplier: cursor.float32(at: speedMultiplierField) ?? 0,
            axisOfRotation: cursor.vector4(at: axisField) ?? SIMD4(),
            unresolved: cursor.unresolved
        )
    }

    var nodeName: String? {
        modifier.name
    }

    var references: [HKBReference] {
        modifier.references
    }

    var summary: String {
        "\(degreesPerSecond) deg/s times \(speedMultiplier)"
    }
}

/// One entry of `hkbKeyframeBonesModifier::m_keyframeInfo`, 48 bytes.
nonisolated struct HKBKeyframeInfo: Equatable {
    let keyframedPosition: SIMD4<Float>
    let keyframedRotation: SIMD4<Float>
    let boneIndex: Int
    let isValid: Bool

    static let stride = 48

    static func decode(_ element: inout HKXObjectCursor, index: Int) -> HKBKeyframeInfo {
        let member = "m_keyframeInfo[\(index)]"
        return HKBKeyframeInfo(
            keyframedPosition: element
                .vector4(at: HKXField(0x00, "\(member).m_keyframedPosition")) ?? SIMD4(),
            keyframedRotation: element
                .vector4(at: HKXField(0x10, "\(member).m_keyframedRotation")) ?? SIMD4(),
            boneIndex: element.int16(at: HKXField(0x20, "\(member).m_boneIndex")) ?? -1,
            isValid: element.bool(at: HKXField(0x22, "\(member).m_isValid")) ?? false
        )
    }
}

/// Decoded `hkbKeyframeBonesModifier`, size 104: pins named bones to explicit
/// transforms, overriding whatever the generator produced for them.
nonisolated struct HKBKeyframeBonesModifier: HKBClass, Equatable {
    let modifier: HKBModifierHeader
    let keyframeInfo: [HKBKeyframeInfo]
    /// `hkbBoneIndexArray` naming which bones are keyframed.
    let keyframedBonesList: HKXPointerTarget?
    let unresolved: [HKXUnresolvedReference]

    static let className = "hkbKeyframeBonesModifier"

    private static let keyframeInfoField = HKXField(0x50, "m_keyframeInfo")
    private static let keyframedBonesListField = HKXField(0x60, "m_keyframedBonesList")

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBKeyframeBonesModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        var infos: [HKBKeyframeInfo] = []
        if let view = cursor.array(at: keyframeInfoField) {
            infos.reserveCapacity(view.count)
            for index in 0 ..< view.count {
                guard
                    var element = graph.element(
                        of: view, index: index, stride: HKBKeyframeInfo.stride
                    )
                else {
                    cursor.recordMiss(keyframeInfoField, .outOfBounds)
                    continue
                }
                infos.append(HKBKeyframeInfo.decode(&element, index: index))
                cursor.absorb(element)
            }
        }
        return HKBKeyframeBonesModifier(
            modifier: header,
            keyframeInfo: infos,
            keyframedBonesList: cursor.pointer(at: keyframedBonesListField),
            unresolved: cursor.unresolved
        )
    }

    var nodeName: String? {
        modifier.name
    }

    var references: [HKBReference] {
        modifier.references
            + HKBReference.optional("m_keyframedBonesList", keyframedBonesList)
    }

    var summary: String {
        "\(keyframeInfo.count) keyframed bones"
    }
}

/// Decoded `hkbGetUpModifier`, size 128: rotates the character upright from a
/// ragdoll pose over a fixed duration.
nonisolated struct HKBGetUpModifier: HKBClass, Equatable {
    let modifier: HKBModifierHeader
    let groundNormal: SIMD4<Float>
    let duration: Float
    let alignWithGroundDuration: Float
    let rootBoneIndex: Int
    let otherBoneIndex: Int
    let anotherBoneIndex: Int
    let unresolved: [HKXUnresolvedReference]

    static let className = "hkbGetUpModifier"

    private static let groundNormalField = HKXField(0x50, "m_groundNormal")
    private static let durationField = HKXField(0x60, "m_duration")
    private static let alignDurationField = HKXField(0x64, "m_alignWithGroundDuration")
    private static let rootBoneField = HKXField(0x68, "m_rootBoneIndex")
    private static let otherBoneField = HKXField(0x6A, "m_otherBoneIndex")
    private static let anotherBoneField = HKXField(0x6C, "m_anotherBoneIndex")

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBGetUpModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        return HKBGetUpModifier(
            modifier: header,
            groundNormal: cursor.vector4(at: groundNormalField) ?? SIMD4(),
            duration: cursor.float32(at: durationField) ?? 0,
            alignWithGroundDuration: cursor.float32(at: alignDurationField) ?? 0,
            rootBoneIndex: cursor.int16(at: rootBoneField) ?? -1,
            otherBoneIndex: cursor.int16(at: otherBoneField) ?? -1,
            anotherBoneIndex: cursor.int16(at: anotherBoneField) ?? -1,
            unresolved: cursor.unresolved
        )
    }

    var nodeName: String? {
        modifier.name
    }

    var references: [HKBReference] {
        modifier.references
    }

    var summary: String {
        "get up over \(duration)s, align \(alignWithGroundDuration)s"
    }
}
