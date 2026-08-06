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
// docs/formats/hkx-behavior-nodes.md.
//
// 64-bit member offsets from ret2end/HKX2Library (MIT); signatures match the
// local SSE files (hkbFootIkControlsModifier 0xE5B6F544,
// hkbPoweredRagdollControlsModifier 0x7CB54065,
// hkbRigidBodyRagdollControlsModifier 0xAA87D1EB, hkbFootIkGains 0xA681B7F0).
// Byte map: docs/formats/hkx-behavior-nodes.md.

import Foundation

/// `hkbFootIkGains`, 48 bytes, embedded as `hkbFootIkControlData::m_gains`:
/// twelve response rates in a fixed order. Kept as a flat array because nothing
/// in this milestone reads an individual gain, and naming twelve floats that
/// M15 may re-derive would be twelve chances to be wrong.
nonisolated struct HKBFootIkGains: Equatable {
    /// In Havok's declared order: on/off, ground ascending, ground descending,
    /// foot planted, foot raised, foot unlock, world-from-model feedback,
    /// error up/down bias, align world-from-model, hip orientation, max knee
    /// angle difference, ankle orientation.
    let gains: [Float]

    static let count = 12
    static let stride = 48

    static func decode(
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
nonisolated struct HKBFootIkLeg: Equatable {
    let groundPosition: SIMD4<Float>
    /// Raised when the foot leaves the ground.
    let ungroundedEvent: HKBEventProperty
    let verticalError: Float
    let hitSomething: Bool
    let isPlantedMS: Bool

    static let stride = 48

    static func decode(_ element: inout HKXObjectCursor, index: Int) -> HKBFootIkLeg {
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
nonisolated struct HKBFootIkControlsModifier: HKBClass, Equatable {
    let modifier: HKBModifierHeader
    let gains: HKBFootIkGains
    let legs: [HKBFootIkLeg]
    let errorOutTranslation: SIMD4<Float>
    let alignWithGroundRotation: SIMD4<Float>
    let unresolved: [HKXUnresolvedReference]

    static let className = "hkbFootIkControlsModifier"

    /// `m_controlData` starts at 0x50 and its only member is `m_gains` at +0.
    private static let gainsOffset = 0x50
    private static let legsField = HKXField(0x80, "m_legs")
    private static let errorOutField = HKXField(0x90, "m_errorOutTranslation")
    private static let alignRotationField = HKXField(0xA0, "m_alignWithGroundRotation")

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
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

    var nodeName: String? {
        modifier.name
    }

    var references: [HKBReference] {
        modifier.references + legs.enumerated().flatMap { index, leg in
            leg.ungroundedEvent.references(named: "m_legs[\(index)].m_ungroundedEvent")
        }
    }

    var summary: String {
        "\(legs.count) legs, \(gains.gains.count) foot-IK gains"
    }
}

/// Decoded `hkbPoweredRagdollControlsModifier`, size 144: drives a ragdoll
/// towards the animated pose with a motor rather than replacing it.
nonisolated struct HKBPoweredRagdollControlsModifier: HKBClass, Equatable {
    let modifier: HKBModifierHeader
    let maxForce: Float
    let tau: Float
    let damping: Float
    let proportionalRecoveryVelocity: Float
    let constantRecoveryVelocity: Float
    /// `hkbBoneIndexArray` of the bones the motor drives.
    let bones: HKXPointerTarget?
    let poseMatchingBone0: Int
    let poseMatchingBone1: Int
    let poseMatchingBone2: Int
    /// `hkbWorldFromModelModeData::WorldFromModelMode`.
    let worldFromModelMode: Int
    /// `hkbBoneWeightArray` scaling the motor per bone.
    let boneWeights: HKXPointerTarget?
    let unresolved: [HKXUnresolvedReference]

    static let className = "hkbPoweredRagdollControlsModifier"

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

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
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

    var nodeName: String? {
        modifier.name
    }

    var references: [HKBReference] {
        modifier.references
            + HKBReference.optional("m_bones", bones)
            + HKBReference.optional("m_boneWeights", boneWeights)
    }

    var summary: String {
        "max force \(maxForce), tau \(tau), damping \(damping)"
    }
}

/// Decoded `hkbRigidBodyRagdollControlsModifier`, size 160: hands the ragdoll
/// to the keyframe-hierarchy solver. Its `m_controlData` embeds a 48-byte
/// `hkaKeyFrameHierarchyUtilityControlData` whose members are M15's business
/// and are deliberately not decoded here; `m_durationToBlend` sits past it.
nonisolated struct HKBRigidBodyRagdollControlsModifier: HKBClass, Equatable {
    let modifier: HKBModifierHeader
    let durationToBlend: Float
    /// `hkbBoneIndexArray` of the bones handed to the ragdoll.
    let bones: HKXPointerTarget?
    let unresolved: [HKXUnresolvedReference]

    static let className = "hkbRigidBodyRagdollControlsModifier"

    private static let durationToBlendField = HKXField(
        0x80, "m_controlData.m_durationToBlend"
    )
    private static let bonesField = HKXField(0x90, "m_bones")

    static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
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

    var nodeName: String? {
        modifier.name
    }

    var references: [HKBReference] {
        modifier.references + HKBReference.optional("m_bones", bones)
    }

    var summary: String {
        "blend over \(durationToBlend)s"
    }
}
