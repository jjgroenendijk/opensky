// Foot-IK and ragdoll control modifiers. They are read and named only; what
// they mean is physics. The 48-byte rigid-body control block stays undecoded
// (Known gaps in docs/formats/hkx-behavior-modifiers.md, which holds the byte
// map). Offsets from HKX2Library (MIT).

import Foundation

/// `hkbFootIkGains`, 48 bytes, embedded as `hkbFootIkControlData::m_gains`:
/// twelve response rates in a fixed order. Kept as a flat array because nothing
/// in this milestone reads an individual gain, and naming twelve floats that
/// M15 may re-derive would be twelve chances to be wrong.
nonisolated public struct HKBFootIkGains: Equatable, Sendable {
    /// In Havok's declared order: on/off, ground ascending, ground descending,
    /// foot planted, foot raised, foot unlock, world-from-model feedback,
    /// error up/down bias, align world-from-model, hip orientation, max knee
    /// angle difference, ankle orientation.
    public let gains: [Float]

    public static let count = 12

    public static func decode(
        _ cursor: inout HKXObjectCursor,
        at offset: Int,
        named member: String
    ) -> HKBFootIkGains {
        HKBFootIkGains(gains: (0 ..< count).map { index in
            cursor.float32(
                at: HKXField(offset + index * 4, "\(member).m_gains[\(index)]")
            ) ?? 0
        })
    }
}

/// One entry of `hkbFootIkControlsModifier::m_legs`, 48 bytes.
nonisolated public struct HKBFootIkLeg: Equatable, Sendable {
    public let groundPosition: SIMD4<Float>
    /// Raised when the foot leaves the ground.
    public let ungroundedEvent: HKBEventProperty
    public let verticalError: Float
    public let hitSomething: Bool
    public let isPlantedMS: Bool

    public static let stride = 48

    public static func decode(_ element: inout HKXObjectCursor, index: Int) -> HKBFootIkLeg {
        let member = "m_legs[\(index)]"
        return HKBFootIkLeg(
            groundPosition: element
                .vector4(at: HKXField(0x00, "\(member).m_groundPosition")) ?? SIMD4(),
            ungroundedEvent: HKBEventProperty.decode(
                &element, at: 0x10, named: "\(member).m_ungroundedEvent"
            ),
            verticalError: element
                .float32(at: HKXField(0x20, "\(member).m_verticalError")) ?? 0,
            hitSomething: element
                .bool(at: HKXField(0x24, "\(member).m_hitSomething")) ?? false,
            isPlantedMS: element
                .bool(at: HKXField(0x25, "\(member).m_isPlantedMS")) ?? false
        )
    }
}

/// Decoded `hkbFootIkControlsModifier`, size 176: feeds the foot-IK solver the
/// per-leg ground contacts the graph believes in.
nonisolated public struct HKBFootIkControlsModifier: HKBClass, Equatable, Sendable {
    public let modifier: HKBModifierHeader
    public let gains: HKBFootIkGains
    public let legs: [HKBFootIkLeg]
    public let errorOutTranslation: SIMD4<Float>
    public let alignWithGroundRotation: SIMD4<Float>
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbFootIkControlsModifier"

    /// `m_controlData` starts at 0x50 and its only member is `m_gains` at +0.
    private static let gainsOffset = 0x50
    private static let legsField = HKXField(0x80, "m_legs")
    private static let errorOutField = HKXField(0x90, "m_errorOutTranslation")
    private static let alignRotationField = HKXField(0xA0, "m_alignWithGroundRotation")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBFootIkControlsModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        let gains = HKBFootIkGains.decode(
            &cursor, at: gainsOffset, named: "m_controlData.m_gains"
        )
        var legs: [HKBFootIkLeg] = []
        if let view = cursor.array(at: legsField) {
            legs.reserveCapacity(view.count)
            for index in 0 ..< view.count {
                guard
                    var element = graph.element(
                        of: view, index: index, stride: HKBFootIkLeg.stride
                    )
                else {
                    cursor.recordMiss(legsField, .outOfBounds)
                    continue
                }
                legs.append(HKBFootIkLeg.decode(&element, index: index))
                cursor.absorb(element)
            }
        }
        return HKBFootIkControlsModifier(
            modifier: header,
            gains: gains,
            legs: legs,
            errorOutTranslation: cursor.vector4(at: errorOutField) ?? SIMD4(),
            alignWithGroundRotation: cursor.vector4(at: alignRotationField) ?? SIMD4(),
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
        "\(legs.count) legs, \(gains.gains.count) foot-IK gains"
    }
}

/// Decoded `hkbPoweredRagdollControlsModifier`, size 144: drives a ragdoll
/// towards the animated pose with a motor rather than replacing it.
nonisolated public struct HKBPoweredRagdollControlsModifier: HKBClass, Equatable, Sendable {
    public let modifier: HKBModifierHeader
    public let maxForce: Float
    public let tau: Float
    public let damping: Float
    public let proportionalRecoveryVelocity: Float
    public let constantRecoveryVelocity: Float
    /// `hkbBoneIndexArray` of the bones the motor drives.
    public let bones: HKXPointerTarget?
    public let poseMatchingBone0: Int
    public let poseMatchingBone1: Int
    public let poseMatchingBone2: Int
    /// `hkbWorldFromModelModeData::WorldFromModelMode`.
    public let worldFromModelMode: Int
    /// `hkbBoneWeightArray` scaling the motor per bone.
    public let boneWeights: HKXPointerTarget?
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbPoweredRagdollControlsModifier"

    private static let maxForceField = HKXField(0x50, "m_controlData.m_maxForce")
    private static let tauField = HKXField(0x54, "m_controlData.m_tau")
    private static let dampingField = HKXField(0x58, "m_controlData.m_damping")
    private static let proportionalField = HKXField(
        0x5C, "m_controlData.m_proportionalRecoveryVelocity"
    )
    private static let constantField = HKXField(
        0x60, "m_controlData.m_constantRecoveryVelocity"
    )
    private static let bonesField = HKXField(0x70, "m_bones")
    private static let poseBone0Field = HKXField(
        0x78, "m_worldFromModelModeData.m_poseMatchingBone0"
    )
    private static let poseBone1Field = HKXField(
        0x7A, "m_worldFromModelModeData.m_poseMatchingBone1"
    )
    private static let poseBone2Field = HKXField(
        0x7C, "m_worldFromModelModeData.m_poseMatchingBone2"
    )
    private static let modeField = HKXField(0x7E, "m_worldFromModelModeData.m_mode")
    private static let boneWeightsField = HKXField(0x80, "m_boneWeights")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBPoweredRagdollControlsModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        return HKBPoweredRagdollControlsModifier(
            modifier: header,
            maxForce: cursor.float32(at: maxForceField) ?? 0,
            tau: cursor.float32(at: tauField) ?? 0,
            damping: cursor.float32(at: dampingField) ?? 0,
            proportionalRecoveryVelocity: cursor.float32(at: proportionalField) ?? 0,
            constantRecoveryVelocity: cursor.float32(at: constantField) ?? 0,
            bones: cursor.pointer(at: bonesField),
            poseMatchingBone0: cursor.int16(at: poseBone0Field) ?? -1,
            poseMatchingBone1: cursor.int16(at: poseBone1Field) ?? -1,
            poseMatchingBone2: cursor.int16(at: poseBone2Field) ?? -1,
            worldFromModelMode: cursor.int8(at: modeField) ?? 0,
            boneWeights: cursor.pointer(at: boneWeightsField),
            unresolved: cursor.unresolved
        )
    }

    public var nodeName: String? {
        modifier.name
    }

    public var references: [HKBReference] {
        modifier.references
            + HKBReference.optional("m_bones", bones)
            + HKBReference.optional("m_boneWeights", boneWeights)
    }

    public var summary: String {
        "max force \(maxForce), tau \(tau), damping \(damping)"
    }
}

/// Decoded `hkbRigidBodyRagdollControlsModifier`, size 160: hands the ragdoll
/// to the keyframe-hierarchy solver. Its `m_controlData` embeds a 48-byte
/// `hkaKeyFrameHierarchyUtilityControlData` whose members are M15's business
/// and are deliberately not decoded here; `m_durationToBlend` sits past it.
nonisolated public struct HKBRigidBodyRagdollControlsModifier: HKBClass, Equatable, Sendable {
    public let modifier: HKBModifierHeader
    public let durationToBlend: Float
    /// `hkbBoneIndexArray` of the bones handed to the ragdoll.
    public let bones: HKXPointerTarget?
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkbRigidBodyRagdollControlsModifier"

    /// The blend `0_master.hkx` authors on its one instance of this class,
    /// `DriveRagdollRB`, read off the local install through
    /// `openskycli hkx meshes\actors\character\behaviors\0_master.hkx`. It is
    /// what a session with no evaluated graph falls back to, so
    /// that the fallback is vanilla's own number rather than an invented one.
    public static let vanillaBlendDuration: Float = 0.5

    private static let durationToBlendField = HKXField(
        0x80, "m_controlData.m_durationToBlend"
    )
    private static let bonesField = HKXField(0x90, "m_bones")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKBRigidBodyRagdollControlsModifier?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let header = HKBModifierHeader.decode(&cursor)
        return HKBRigidBodyRagdollControlsModifier(
            modifier: header,
            durationToBlend: cursor.float32(at: durationToBlendField) ?? 0,
            bones: cursor.pointer(at: bonesField),
            unresolved: cursor.unresolved
        )
    }

    public var nodeName: String? {
        modifier.name
    }

    public var references: [HKBReference] {
        modifier.references + HKBReference.optional("m_bones", bones)
    }

    public var summary: String {
        "blend over \(durationToBlend)s"
    }
}
