// The ragdoll containers of a skeleton file: the ragdoll instance, the mapper
// between the ragdoll and the animation rig, and the physics system that holds
// the bodies. Offsets from HKX2Library (MIT). Byte map: docs/formats/hkx-physics.md.

import Foundation

/// Decoded `hkaRagdollInstance`, size 80: one rigid body per ragdoll bone.
nonisolated public struct HKARagdollInstance: HKBClass, Equatable, Sendable {
    public let rigidBodies: [HKXPointerTarget?]
    public let constraints: [HKXPointerTarget?]
    /// Ragdoll skeleton bone -> index into `rigidBodies`, or -1.
    public let boneToRigidBodyMap: [Int]
    /// The ragdoll's own `hkaSkeleton`, not the animation rig.
    public let skeleton: HKXPointerTarget?
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkaRagdollInstance"

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKARagdollInstance?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        return HKARagdollInstance(
            rigidBodies: cursor.pointerArray(at: HKXField(0x10, "m_rigidBodies")),
            constraints: cursor.pointerArray(at: HKXField(0x20, "m_constraints")),
            boneToRigidBodyMap: cursor.int32Array(at: HKXField(0x30, "m_boneToRigidBodyMap"))
                ?? [],
            skeleton: cursor.pointer(at: HKXField(0x40, "m_skeleton")),
            unresolved: cursor.unresolved
        )
    }

    public var references: [HKBReference] {
        HKBReference.each("m_rigidBodies", rigidBodies)
            + HKBReference.each("m_constraints", constraints)
            + HKBReference.optional("m_skeleton", skeleton)
    }

    public var summary: String {
        "\(rigidBodies.count) bodies, \(constraints.count) constraints"
    }
}

/// Decoded `hkaSkeletonMapper`, size 144: how a pose of skeleton A becomes a
/// pose of skeleton B. A skeleton file has two, ragdoll to rig and back.
nonisolated public struct HKASkeletonMapper: HKBClass, Equatable, Sendable {
    /// One bone of A that drives one bone of B.
    public struct SimpleMapping: Equatable, Sendable {
        public let boneA: Int
        public let boneB: Int
        public let aFromBTransform: HKQsTransform
    }

    /// A chain of A bones that drives a chain of B bones.
    public struct ChainMapping: Equatable, Sendable {
        public let startBoneA: Int
        public let endBoneA: Int
        public let startBoneB: Int
        public let endBoneB: Int
    }

    public let skeletonA: HKXPointerTarget?
    public let skeletonB: HKXPointerTarget?
    public let simpleMappings: [SimpleMapping]
    public let chainMappings: [ChainMapping]
    public let unmappedBones: [Int]
    public let keepUnmappedLocal: Bool
    /// `hkaSkeletonMapperData::MappingType`: 0 ragdoll, 1 retargeting.
    public let mappingType: Int
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkaSkeletonMapper"

    private static let simpleStride = 64
    private static let chainStride = 112

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKASkeletonMapper?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let simple = cursor.structArray(
            at: HKXField(0x20, "m_mapping.m_simpleMappings"), stride: simpleStride
        ) { element, index in
            let member = "m_mapping.m_simpleMappings[\(index)]"
            return SimpleMapping(
                boneA: element.int16(at: HKXField(0, "\(member).m_boneA")) ?? -1,
                boneB: element.int16(at: HKXField(2, "\(member).m_boneB")) ?? -1,
                aFromBTransform: HKQsTransform.decode(
                    &element, at: 16, named: "\(member).m_aFromBTransform"
                )
            )
        }
        let chains = cursor.structArray(
            at: HKXField(0x30, "m_mapping.m_chainMappings"), stride: chainStride
        ) { element, index in
            let member = "m_mapping.m_chainMappings[\(index)]"
            return ChainMapping(
                startBoneA: element.int16(at: HKXField(0, "\(member).m_startBoneA")) ?? -1,
                endBoneA: element.int16(at: HKXField(2, "\(member).m_endBoneA")) ?? -1,
                startBoneB: element.int16(at: HKXField(4, "\(member).m_startBoneB")) ?? -1,
                endBoneB: element.int16(at: HKXField(6, "\(member).m_endBoneB")) ?? -1
            )
        }
        return HKASkeletonMapper(
            skeletonA: cursor.pointer(at: HKXField(0x10, "m_mapping.m_skeletonA")),
            skeletonB: cursor.pointer(at: HKXField(0x18, "m_mapping.m_skeletonB")),
            simpleMappings: simple,
            chainMappings: chains,
            unmappedBones: cursor.int16Array(at: HKXField(0x40, "m_mapping.m_unmappedBones"))
                ?? [],
            keepUnmappedLocal: cursor.bool(at: HKXField(0x80, "m_mapping.m_keepUnmappedLocal"))
                ?? false,
            mappingType: cursor.int32(at: HKXField(0x84, "m_mapping.m_mappingType")) ?? 0,
            unresolved: cursor.unresolved
        )
    }

    public var references: [HKBReference] {
        HKBReference.optional("m_mapping.m_skeletonA", skeletonA)
            + HKBReference.optional("m_mapping.m_skeletonB", skeletonB)
    }

    public var summary: String {
        "\(simpleMappings.count) simple, \(chainMappings.count) chain mappings"
    }
}

/// Decoded `hkpPhysicsData`, size 40: the physics systems of a file.
nonisolated public struct HKPPhysicsData: HKBClass, Equatable, Sendable {
    public let systems: [HKXPointerTarget?]
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkpPhysicsData"

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKPPhysicsData?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        return HKPPhysicsData(
            systems: cursor.pointerArray(at: HKXField(0x18, "m_systems")),
            unresolved: cursor.unresolved
        )
    }

    public var references: [HKBReference] {
        HKBReference.each("m_systems", systems)
    }

    public var summary: String {
        "\(systems.count) systems"
    }
}

/// Decoded `hkpPhysicsSystem`, size 104: bodies and constraints that act as one.
nonisolated public struct HKPPhysicsSystem: HKBClass, Equatable, Sendable {
    public let name: String?
    public let rigidBodies: [HKXPointerTarget?]
    public let constraints: [HKXPointerTarget?]
    public let isActive: Bool
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkpPhysicsSystem"

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKPPhysicsSystem?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        return HKPPhysicsSystem(
            name: cursor.string(at: HKXField(0x50, "m_name")),
            rigidBodies: cursor.pointerArray(at: HKXField(0x10, "m_rigidBodies")),
            constraints: cursor.pointerArray(at: HKXField(0x20, "m_constraints")),
            isActive: cursor.bool(at: HKXField(0x60, "m_active")) ?? false,
            unresolved: cursor.unresolved
        )
    }

    public var references: [HKBReference] {
        HKBReference.each("m_rigidBodies", rigidBodies)
            + HKBReference.each("m_constraints", constraints)
    }

    public var summary: String {
        "\(name ?? "<unnamed>"): \(rigidBodies.count) bodies, \(constraints.count) constraints"
    }
}
