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
// docs/formats/hkx-behavior-modifiers.md.

import Foundation

/// Decoded `hkbTwistModifier`, size 144: spreads one rotation across a chain of
/// bones, which is how the player's spine follows the aim direction.
nonisolated package struct HKBTwistModifier: HKBClass, Equatable {
    package let modifier: HKBModifierHeader
    package let axisOfRotation: SIMD4<Float>
    package let twistAngle: Float
    package let startBoneIndex: Int
    package let endBoneIndex: Int
    /// `hkbTwistModifier::SetAngleMethod`: 0 linear, 1 ramped.
    package let setAngleMethod: Int
    /// `hkbTwistModifier::RotationAxisCoordinates`: 0 model space, 1 local.
    package let rotationAxisCoordinates: Int
    package let isAdditive: Bool
    package let unresolved: [HKXUnresolvedReference]

    package static let className = "hkbTwistModifier"

    private static let axisField = HKXField(0x50, "m_axisOfRotation")
    private static let twistAngleField = HKXField(0x60, "m_twistAngle")
    private static let startBoneField = HKXField(0x64, "m_startBoneIndex")
    private static let endBoneField = HKXField(0x66, "m_endBoneIndex")
    private static let setAngleMethodField = HKXField(0x68, "m_setAngleMethod")
    private static let axisCoordinatesField = HKXField(0x69, "m_rotationAxisCoordinates")
    private static let isAdditiveField = HKXField(0x6A, "m_isAdditive")

    package static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
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

    package var nodeName: String? {
        modifier.name
    }

    package var references: [HKBReference] {
        modifier.references
    }

    package var summary: String {
        "twist \(twistAngle) rad over bones \(startBoneIndex)-\(endBoneIndex)"
    }
}

/// Decoded `hkbRotateCharacterModifier`, size 128: turns the whole character at
/// a fixed rate, used by the turn-in-place states.
nonisolated package struct HKBRotateCharacterModifier: HKBClass, Equatable {
    package let modifier: HKBModifierHeader
    package let degreesPerSecond: Float
    package let speedMultiplier: Float
    package let axisOfRotation: SIMD4<Float>
    package let unresolved: [HKXUnresolvedReference]

    package static let className = "hkbRotateCharacterModifier"

    private static let degreesPerSecondField = HKXField(0x50, "m_degreesPerSecond")
    private static let speedMultiplierField = HKXField(0x54, "m_speedMultiplier")
    private static let axisField = HKXField(0x60, "m_axisOfRotation")

    package static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
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

    package var nodeName: String? {
        modifier.name
    }

    package var references: [HKBReference] {
        modifier.references
    }

    package var summary: String {
        "\(degreesPerSecond) deg/s times \(speedMultiplier)"
    }
}

/// One entry of `hkbKeyframeBonesModifier::m_keyframeInfo`, 48 bytes.
nonisolated package struct HKBKeyframeInfo: Equatable {
    package let keyframedPosition: SIMD4<Float>
    package let keyframedRotation: SIMD4<Float>
    package let boneIndex: Int
    package let isValid: Bool

    package static let stride = 48

    package static func decode(_ element: inout HKXObjectCursor, index: Int) -> HKBKeyframeInfo {
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
nonisolated package struct HKBKeyframeBonesModifier: HKBClass, Equatable {
    package let modifier: HKBModifierHeader
    package let keyframeInfo: [HKBKeyframeInfo]
    /// `hkbBoneIndexArray` naming which bones are keyframed.
    package let keyframedBonesList: HKXPointerTarget?
    package let unresolved: [HKXUnresolvedReference]

    package static let className = "hkbKeyframeBonesModifier"

    private static let keyframeInfoField = HKXField(0x50, "m_keyframeInfo")
    private static let keyframedBonesListField = HKXField(0x60, "m_keyframedBonesList")

    package static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
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

    package var nodeName: String? {
        modifier.name
    }

    package var references: [HKBReference] {
        modifier.references
            + HKBReference.optional("m_keyframedBonesList", keyframedBonesList)
    }

    package var summary: String {
        "\(keyframeInfo.count) keyframed bones"
    }
}

/// Decoded `hkbGetUpModifier`, size 128: rotates the character upright from a
/// ragdoll pose over a fixed duration.
nonisolated package struct HKBGetUpModifier: HKBClass, Equatable {
    package let modifier: HKBModifierHeader
    package let groundNormal: SIMD4<Float>
    package let duration: Float
    package let alignWithGroundDuration: Float
    package let rootBoneIndex: Int
    package let otherBoneIndex: Int
    package let anotherBoneIndex: Int
    package let unresolved: [HKXUnresolvedReference]

    package static let className = "hkbGetUpModifier"

    private static let groundNormalField = HKXField(0x50, "m_groundNormal")
    private static let durationField = HKXField(0x60, "m_duration")
    private static let alignDurationField = HKXField(0x64, "m_alignWithGroundDuration")
    private static let rootBoneField = HKXField(0x68, "m_rootBoneIndex")
    private static let otherBoneField = HKXField(0x6A, "m_otherBoneIndex")
    private static let anotherBoneField = HKXField(0x6C, "m_anotherBoneIndex")

    package static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
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

    package var nodeName: String? {
        modifier.name
    }

    package var references: [HKBReference] {
        modifier.references
    }

    package var summary: String {
        "get up over \(duration)s, align \(alignWithGroundDuration)s"
    }
}
