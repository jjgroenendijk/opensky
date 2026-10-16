// Stock Havok classes that had no decoder: the foot IK solver modifier, the
// reference pose generator, and the vector transform modifier.
// Byte map: docs/formats/hkx-behavior-modifiers.md.

import Foundation

nonisolated extension HKBFootIkGains {
    /// Havok's member names, in the order of `gains`.
    public static let memberNames = [
        "onOffGain", "groundAscendingGain", "groundDescendingGain", "footPlantedGain",
        "footRaisedGain", "footUnlockGain", "worldFromModelFeedbackGain", "errorUpDownBias",
        "alignWorldFromModelGain", "hipOrientationGain", "maxKneeAngleDifference",
        "ankleOrientationGain"
    ]

    public func value(_ name: String) -> Float {
        guard let index = Self.memberNames.firstIndex(of: name), gains.indices.contains(index)
        else { return 0 }
        return gains[index]
    }
}

/// One `hkbFootIkModifierLeg`, 160 bytes.
nonisolated public struct HKBFootIkModifierLeg: Equatable, Sendable {
    public let kneeAxisLS: SIMD4<Float>
    public let footEndLS: SIMD4<Float>
    public let ungroundedEvent: HKBEventProperty
    public let footPlantedAnkleHeightMS: Float
    public let footRaisedAnkleHeightMS: Float
    public let maxAnkleHeightMS: Float
    public let minAnkleHeightMS: Float
    public let maxKneeAngleDegrees: Float
    public let minKneeAngleDegrees: Float
    public let maxAnkleAngleDegrees: Float
    public let hipIndex: Int
    public let kneeIndex: Int
    public let ankleIndex: Int

    public static let stride = 160

    static func decode(_ element: inout HKXObjectCursor, index: Int) -> HKBFootIkModifierLeg {
        let member = "m_legs[\(index)]"
        func real(_ offset: Int, _ name: String) -> Float {
            element.float32(at: HKXField(offset, "\(member).\(name)")) ?? 0
        }
        func bone(_ offset: Int, _ name: String) -> Int {
            element.int16(at: HKXField(offset, "\(member).\(name)")) ?? -1
        }
        return HKBFootIkModifierLeg(
            kneeAxisLS: element.vector4(at: HKXField(0x40, "\(member).m_kneeAxisLS")) ?? SIMD4(),
            footEndLS: element.vector4(at: HKXField(0x50, "\(member).m_footEndLS")) ?? SIMD4(),
            ungroundedEvent: HKBEventProperty.decode(
                &element, at: 0x60, named: "\(member).m_ungroundedEvent"
            ),
            footPlantedAnkleHeightMS: real(0x70, "m_footPlantedAnkleHeightMS"),
            footRaisedAnkleHeightMS: real(0x74, "m_footRaisedAnkleHeightMS"),
            maxAnkleHeightMS: real(0x78, "m_maxAnkleHeightMS"),
            minAnkleHeightMS: real(0x7C, "m_minAnkleHeightMS"),
            maxKneeAngleDegrees: real(0x80, "m_maxKneeAngleDegrees"),
            minKneeAngleDegrees: real(0x84, "m_minKneeAngleDegrees"),
            maxAnkleAngleDegrees: real(0x8C, "m_maxAnkleAngleDegrees"),
            hipIndex: bone(0x90, "m_hipIndex"),
            kneeIndex: bone(0x92, "m_kneeIndex"),
            ankleIndex: bone(0x94, "m_ankleIndex")
        )
    }
}

/// Decoded `hkbFootIkModifier`, size 256: plants each leg's foot on the ground
/// with a two-bone IK solve from hip to ankle.
nonisolated public struct HKBFootIkModifier: HKBClass, Equatable, Sendable {
    public let modifier: HKBModifierHeader
    public let gains: HKBFootIkGains
    public let legs: [HKBFootIkModifierLeg]
    public let raycastDistanceUp: Float
    public let raycastDistanceDown: Float
    public let originalGroundHeightMS: Float
    public let verticalOffset: Float
    public let useTrackData: Bool
    public let lockFeetWhenPlanted: Bool
    public let alignMode: Int
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbFootIkModifier"

    private static let gainsOffset = 0x50
    private static let legsField = HKXField(0x80, "m_legs")
    private static let upField = HKXField(0x90, "m_raycastDistanceUp")
    private static let downField = HKXField(0x94, "m_raycastDistanceDown")
    private static let groundHeightField = HKXField(0x98, "m_originalGroundHeightMS")
    private static let verticalOffsetField = HKXField(0xC0, "m_verticalOffset")
    private static let useTrackDataField = HKXField(0xD4, "m_useTrackData")
    private static let lockFeetField = HKXField(0xD5, "m_lockFeetWhenPlanted")
    private static let alignModeField = HKXField(0xD7, "m_alignMode")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBFootIkModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        let gains = HKBFootIkGains.decode(&cursor, at: gainsOffset, named: "m_gains")
        let legs = cursor.structArray(at: legsField, stride: HKBFootIkModifierLeg.stride) {
            HKBFootIkModifierLeg.decode(&$0, index: $1)
        }
        return HKBFootIkModifier(
            modifier: header, gains: gains, legs: legs,
            raycastDistanceUp: cursor.float32(at: upField) ?? 0,
            raycastDistanceDown: cursor.float32(at: downField) ?? 0,
            originalGroundHeightMS: cursor.float32(at: groundHeightField) ?? 0,
            verticalOffset: cursor.float32(at: verticalOffsetField) ?? 0,
            useTrackData: cursor.bool(at: useTrackDataField) ?? false,
            lockFeetWhenPlanted: cursor.bool(at: lockFeetField) ?? false,
            alignMode: cursor.int8(at: alignModeField) ?? 0,
            unresolved: cursor.unresolved
        )
    }

    public var nodeName: String? {
        modifier.name
    }

    public var references: [HKBReference] {
        modifier.references + legs.enumerated().flatMap { index, leg in
            leg.ungroundedEvent.references(named: "m_legs[\(index)].m_ungroundedEvent")
        }
    }

    public var summary: String {
        "\(legs.count) legs, ground height \(originalGroundHeightMS)"
    }
}

/// Decoded `hkbReferencePoseGenerator`, size 80: produces the skeleton's
/// reference pose. Its one member, the skeleton pointer, is not serialized.
nonisolated public struct HKBReferencePoseGenerator: HKBClass, Equatable, Sendable {
    public let node: HKBNodeHeader
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbReferencePoseGenerator"

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBReferencePoseGenerator?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBNodeHeader.decode(&cursor)
        return HKBReferencePoseGenerator(node: header, unresolved: cursor.unresolved)
    }

    public var nodeName: String? {
        node.name
    }

    public var references: [HKBReference] {
        node.references
    }

    public var summary: String {
        "reference pose"
    }
}

/// Decoded `hkbTransformVectorModifier`, size 160: writes `m_vectorIn`
/// rotated and translated (or the inverse) to `m_vectorOut`.
nonisolated public struct HKBTransformVectorModifier: HKBClass, Equatable, Sendable {
    public let modifier: HKBModifierHeader
    /// `hkQuaternion` as (x, y, z, w).
    public let rotation: SIMD4<Float>
    public let translation: SIMD4<Float>
    public let vectorIn: SIMD4<Float>
    public let vectorOut: SIMD4<Float>
    public let rotateOnly: Bool
    public let inverse: Bool
    public let computeOnActivate: Bool
    public let computeOnModify: Bool
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbTransformVectorModifier"

    private static let rotationField = HKXField(0x50, "m_rotation")
    private static let translationField = HKXField(0x60, "m_translation")
    private static let vectorInField = HKXField(0x70, "m_vectorIn")
    private static let vectorOutField = HKXField(0x80, "m_vectorOut")
    private static let rotateOnlyField = HKXField(0x90, "m_rotateOnly")
    private static let inverseField = HKXField(0x91, "m_inverse")
    private static let onActivateField = HKXField(0x92, "m_computeOnActivate")
    private static let onModifyField = HKXField(0x93, "m_computeOnModify")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBTransformVectorModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        return HKBTransformVectorModifier(
            modifier: header,
            rotation: cursor.vector4(at: rotationField) ?? SIMD4(0, 0, 0, 1),
            translation: cursor.vector4(at: translationField) ?? SIMD4(),
            vectorIn: cursor.vector4(at: vectorInField) ?? SIMD4(),
            vectorOut: cursor.vector4(at: vectorOutField) ?? SIMD4(),
            rotateOnly: cursor.bool(at: rotateOnlyField) ?? false,
            inverse: cursor.bool(at: inverseField) ?? false,
            computeOnActivate: cursor.bool(at: onActivateField) ?? false,
            computeOnModify: cursor.bool(at: onModifyField) ?? false,
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
        "rotate only \(rotateOnly), inverse \(inverse)"
    }
}
