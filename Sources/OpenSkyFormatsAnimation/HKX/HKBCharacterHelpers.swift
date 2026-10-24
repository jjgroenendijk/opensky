// Classes a character or an object graph points at beside its behaviour nodes:
// the mirror map, the foot IK driver setup, and the generator that plays a NIF
// controller sequence. Offsets from HKX2Library (MIT). Byte maps:
// docs/formats/hkx-behavior.md and docs/formats/hkx-behavior-nodes.md.

import Foundation

/// Decoded `hkbMirroredSkeletonInfo`, size 48: the mirror plane and, per bone,
/// the bone on the other side.
nonisolated public struct HKBMirroredSkeletonInfo: HKBClass, Equatable, Sendable {
    public let mirrorAxis: SIMD4<Float>
    /// Bone -> its mirror bone; a centre bone maps to itself.
    public let bonePairMap: [Int]
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbMirroredSkeletonInfo"

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBMirroredSkeletonInfo?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        return HKBMirroredSkeletonInfo(
            mirrorAxis: cursor.vector4(at: HKXField(0x10, "m_mirrorAxis")) ?? SIMD4(),
            bonePairMap: cursor.int16Array(at: HKXField(0x20, "m_bonePairMap")) ?? [],
            unresolved: cursor.unresolved
        )
    }

    public var summary: String {
        "mirror axis \(mirrorAxis), \(bonePairMap.count) bones"
    }
}

/// Decoded `hkbFootIkDriverInfo`, size 80: the legs and ray lengths the foot IK
/// solver of a character uses.
nonisolated public struct HKBFootIkDriverInfo: HKBClass, Equatable, Sendable {
    /// One leg: its three bones and how far the ankle may move.
    public struct Leg: Equatable, Sendable {
        public let hipIndex: Int
        public let kneeIndex: Int
        public let ankleIndex: Int
        public let footPlantedAnkleHeightMS: Float
        public let footRaisedAnkleHeightMS: Float
        public let maxKneeAngleDegrees: Float
        public let minKneeAngleDegrees: Float
    }

    public let legs: [Leg]
    public let raycastDistanceUp: Float
    public let raycastDistanceDown: Float
    public let originalGroundHeightMS: Float
    public let lockFeetWhenPlanted: Bool
    public let isQuadrupedNarrow: Bool
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbFootIkDriverInfo"

    private static let legStride = 96

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBFootIkDriverInfo?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let field = HKXField(0x10, "m_legs")
        let legs = cursor.structArray(at: field, stride: legStride) { element, index in
            let member = "m_legs[\(index)]"
            func real(_ offset: Int, _ name: String) -> Float {
                element.float32(at: HKXField(offset, "\(member).\(name)")) ?? 0
            }
            return Leg(
                hipIndex: element.int16(at: HKXField(0x4C, "\(member).m_hipIndex")) ?? -1,
                kneeIndex: element.int16(at: HKXField(0x4E, "\(member).m_kneeIndex")) ?? -1,
                ankleIndex: element.int16(at: HKXField(0x50, "\(member).m_ankleIndex")) ?? -1,
                footPlantedAnkleHeightMS: real(0x30, "m_footPlantedAnkleHeightMS"),
                footRaisedAnkleHeightMS: real(0x34, "m_footRaisedAnkleHeightMS"),
                maxKneeAngleDegrees: real(0x40, "m_maxKneeAngleDegrees"),
                minKneeAngleDegrees: real(0x44, "m_minKneeAngleDegrees")
            )
        }
        return HKBFootIkDriverInfo(
            legs: legs,
            raycastDistanceUp: cursor.float32(at: HKXField(0x20, "m_raycastDistanceUp")) ?? 0,
            raycastDistanceDown: cursor.float32(at: HKXField(0x24, "m_raycastDistanceDown"))
                ?? 0,
            originalGroundHeightMS: cursor.float32(
                at: HKXField(0x28, "m_originalGroundHeightMS")
            ) ?? 0,
            lockFeetWhenPlanted: cursor.bool(at: HKXField(0x40, "m_lockFeetWhenPlanted"))
                ?? false,
            isQuadrupedNarrow: cursor.bool(at: HKXField(0x42, "m_isQuadrupedNarrow")) ?? false,
            unresolved: cursor.unresolved
        )
    }

    public var summary: String {
        "\(legs.count) legs, ray \(raycastDistanceUp) up, \(raycastDistanceDown) down"
    }
}

/// Decoded `BGSGamebryoSequenceGenerator`, size 112: plays the NIF controller
/// sequence of the graph's own mesh, such as a trap's `Forward` sequence.
nonisolated public struct BGSGamebryoSequenceGenerator: HKBClass, Equatable, Sendable {
    public let node: HKBNodeHeader
    /// The `NiControllerSequence` name in the object's NIF.
    public let sequence: String?
    /// `BlendModeFunction`: 0 none, 1 min, 2 max, 3 add, 4 subtract.
    public let blendModeFunction: Int
    public let percent: Float
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "BGSGamebryoSequenceGenerator"

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> BGSGamebryoSequenceGenerator?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let node = HKBNodeHeader.decode(&cursor)
        return BGSGamebryoSequenceGenerator(
            node: node,
            sequence: cursor.string(at: HKXField(0x48, "m_pSequence")),
            blendModeFunction: cursor.int8(at: HKXField(0x50, "m_eBlendModeFunction")) ?? 0,
            percent: cursor.float32(at: HKXField(0x54, "m_fPercent")) ?? 0,
            unresolved: cursor.unresolved
        )
    }

    public var nodeName: String? {
        node.name
    }

    public var references: [HKBReference] {
        node.references
    }

    public var summary: String {
        "sequence \(sequence ?? "<none>"), percent \(percent)"
    }
}
