// The foot-IK and ragdoll control modifiers (todo 14.2). These are the
// modifiers that hand the behavior graph's intent to the physics side: which
// bones the ragdoll drives, how hard, and where each foot should be planted.
//
// They are decoded because the milestone's full-graph rule gives every census
// class a decoder. What they *mean* is physics, which the scope decision puts in
// M15, so nothing here interprets a gain or a control-data block; the fields are
// read and named and that is all.
//
// `hkbRigidBodyRagdollControlsModifier::m_controlData` embeds a 48-byte
// `hkaKeyFrameHierarchyUtilityControlData`, an hka physics class rather than an
// hkb behavior one. Its members are not confirmed against the local files, so
// this decoder reads the two members the behavior graph itself addresses —
// `m_durationToBlend` past the block, and the bone list — and leaves the block
// itself undecoded. See the "Known gaps" section of
// docs/formats/hkx-behavior-modifiers.md.
//
// 64-bit member offsets from ret2end/HKX2Library (MIT); signatures match the
// local SSE files (hkbFootIkControlsModifier 0xE5B6F544,
// hkbPoweredRagdollControlsModifier 0x7CB54065,
// hkbRigidBodyRagdollControlsModifier 0xAA87D1EB, hkbFootIkGains 0xA681B7F0).
// Byte map: docs/formats/hkx-behavior-modifiers.md.

import Foundation

/// `hkbFootIkGains`, 48 bytes, embedded as `hkbFootIkControlData::m_gains`:
/// twelve response rates in a fixed order. Kept as a flat array because nothing
/// in this milestone reads an individual gain, and naming twelve floats that
/// M15 may re-derive would be twelve chances to be wrong.
nonisolated package struct HKBFootIkGains: Equatable {
    /// In Havok's declared order: on/off, ground ascending, ground descending,
    /// foot planted, foot raised, foot unlock, world-from-model feedback,
    /// error up/down bias, align world-from-model, hip orientation, max knee
    /// angle difference, ankle orientation.
    package let gains: [Float]

    package static let count = 12
    package static let stride = 48

    package static func decode(
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
nonisolated package struct HKBFootIkLeg: Equatable {
    package let groundPosition: SIMD4<Float>
    /// Raised when the foot leaves the ground.
    package let ungroundedEvent: HKBEventProperty
    package let verticalError: Float
    package let hitSomething: Bool
    package let isPlantedMS: Bool

    package static let stride = 48

    package static func decode(_ element: inout HKXObjectCursor, index: Int) -> HKBFootIkLeg {
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
nonisolated package struct HKBFootIkControlsModifier: HKBClass, Equatable {
    package let modifier: HKBModifierHeader
    package let gains: HKBFootIkGains
    package let legs: [HKBFootIkLeg]
    package let errorOutTranslation: SIMD4<Float>
    package let alignWithGroundRotation: SIMD4<Float>
    package let unresolved: [HKXUnresolvedReference]

    package static let className = "hkbFootIkControlsModifier"

    /// `m_controlData` starts at 0x50 and its only member is `m_gains` at +0.
    private static let gainsOffset = 0x50
    private static let legsField = HKXField(0x80, "m_legs")
    private static let errorOutField = HKXField(0x90, "m_errorOutTranslation")
    private static let alignRotationField = HKXField(0xA0, "m_alignWithGroundRotation")

    package static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
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

    package var nodeName: String? {
        modifier.name
    }

    package var references: [HKBReference] {
        modifier.references + legs.enumerated().flatMap { index, leg in
            leg.ungroundedEvent.references(named: "m_legs[\(index)].m_ungroundedEvent")
        }
    }

    package var summary: String {
        "\(legs.count) legs, \(gains.gains.count) foot-IK gains"
    }
}

/// Decoded `hkbPoweredRagdollControlsModifier`, size 144: drives a ragdoll
/// towards the animated pose with a motor rather than replacing it.
nonisolated package struct HKBPoweredRagdollControlsModifier: HKBClass, Equatable {
    package let modifier: HKBModifierHeader
    package let maxForce: Float
    package let tau: Float
    package let damping: Float
    package let proportionalRecoveryVelocity: Float
    package let constantRecoveryVelocity: Float
    /// `hkbBoneIndexArray` of the bones the motor drives.
    package let bones: HKXPointerTarget?
    package let poseMatchingBone0: Int
    package let poseMatchingBone1: Int
    package let poseMatchingBone2: Int
    /// `hkbWorldFromModelModeData::WorldFromModelMode`.
    package let worldFromModelMode: Int
    /// `hkbBoneWeightArray` scaling the motor per bone.
    package let boneWeights: HKXPointerTarget?
    package let unresolved: [HKXUnresolvedReference]

    package static let className = "hkbPoweredRagdollControlsModifier"

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

    package static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
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

    package var nodeName: String? {
        modifier.name
    }

    package var references: [HKBReference] {
        modifier.references
            + HKBReference.optional("m_bones", bones)
            + HKBReference.optional("m_boneWeights", boneWeights)
    }

    package var summary: String {
        "max force \(maxForce), tau \(tau), damping \(damping)"
    }
}

/// Decoded `hkbRigidBodyRagdollControlsModifier`, size 160: hands the ragdoll
/// to the keyframe-hierarchy solver. Its `m_controlData` embeds a 48-byte
/// `hkaKeyFrameHierarchyUtilityControlData` whose members are M15's business
/// and are deliberately not decoded here; `m_durationToBlend` sits past it.
nonisolated package struct HKBRigidBodyRagdollControlsModifier: HKBClass, Equatable {
    package let modifier: HKBModifierHeader
    package let durationToBlend: Float
    /// `hkbBoneIndexArray` of the bones handed to the ragdoll.
    package let bones: HKXPointerTarget?
    package let unresolved: [HKXUnresolvedReference]

    package static let className = "hkbRigidBodyRagdollControlsModifier"

    /// The blend `0_master.hkx` authors on its one instance of this class,
    /// `DriveRagdollRB`, read off the local install through
    /// `openskycli hkx meshes\actors\character\behaviors\0_master.hkx`. It is
    /// what a session with no evaluated graph falls back to (issue #197), so
    /// that the fallback is vanilla's own number rather than an invented one.
    package static let vanillaBlendDuration: Float = 0.5

    private static let durationToBlendField = HKXField(
        0x80, "m_controlData.m_durationToBlend"
    )
    private static let bonesField = HKXField(0x90, "m_bones")

    package static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
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

    package var nodeName: String? {
        modifier.name
    }

    package var references: [HKBReference] {
        modifier.references + HKBReference.optional("m_bones", bones)
    }

    package var summary: String {
        "blend over \(durationToBlend)s"
    }
}
