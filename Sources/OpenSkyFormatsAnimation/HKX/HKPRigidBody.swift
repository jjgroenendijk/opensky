// hkpRigidBody and hkpConstraintInstance decode: the bone bodies and joints of a
// skeleton's ragdoll. Offsets from HKX2Library (MIT). Byte map:
// docs/formats/hkx-physics.md.

import Foundation
import simd

/// `hkHalf`: the upper 16 bits of a 32-bit float. The real files confirm it:
/// `m_gravityFactor` reads `0x3F80`, which is 1.0 (docs/formats/hkx-physics.md).
nonisolated public enum HKHalf {
    public static func value(_ raw: Int) -> Float {
        Float(bitPattern: UInt32(truncatingIfNeeded: raw) << 16)
    }
}

/// Decoded `hkpRigidBody`, size 720. Only the members a ragdoll needs are read:
/// the shape, the material, the mass, and the motion state.
nonisolated public struct HKPRigidBody: HKBClass, Equatable, Sendable {
    public let name: String?
    public let shape: HKXPointerTarget?
    public let collisionFilterInfo: UInt32
    /// `hkpMaterial::ResponseType`; 1 is a rigid contact response.
    public let responseType: Int
    public let friction: Float
    public let restitution: Float
    /// `hkpMotion::MotionType`, such as 2 for a dynamic box inertia body.
    public let motionType: Int
    /// The body's place in its system's space.
    public let transform: HKTransform
    public let centerOfMassLocal: SIMD3<Float>
    /// The inverse of the inertia diagonal, then the inverse mass.
    public let inertiaAndMassInverse: SIMD4<Float>
    public let linearDamping: Float
    public let angularDamping: Float
    public let gravityFactor: Float
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkpRigidBody"

    private static let shapeField = HKXField(0x20, "m_collidable.m_shape")
    private static let filterField = HKXField(
        0x4C, "m_collidable.m_broadPhaseHandle.m_collisionFilterInfo"
    )
    private static let nameField = HKXField(0xB0, "m_name")
    private static let responseTypeField = HKXField(0xD0, "m_material.m_responseType")
    private static let frictionField = HKXField(0xD4, "m_material.m_friction")
    private static let restitutionField = HKXField(0xD8, "m_material.m_restitution")
    private static let motionTypeField = HKXField(0x160, "m_motion.m_type")
    private static let transformOffset = 0x170
    private static let centerOfMassField = HKXField(
        0x1F0, "m_motion.m_motionState.m_sweptTransform.m_centerOfMassLocal"
    )
    private static let linearDampingField = HKXField(
        0x214, "m_motion.m_motionState.m_linearDamping"
    )
    private static let angularDampingField = HKXField(
        0x216, "m_motion.m_motionState.m_angularDamping"
    )
    private static let inertiaField = HKXField(0x220, "m_motion.m_inertiaAndMassInv")
    private static let gravityFactorField = HKXField(0x282, "m_motion.m_gravityFactor")

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKPRigidBody?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        return HKPRigidBody(
            name: cursor.string(at: nameField),
            shape: cursor.pointer(at: shapeField),
            collisionFilterInfo: cursor.uint32(at: filterField) ?? 0,
            responseType: cursor.int8(at: responseTypeField) ?? 0,
            friction: cursor.float32(at: frictionField) ?? 0,
            restitution: cursor.float32(at: restitutionField) ?? 0,
            motionType: Int(cursor.uint8(at: motionTypeField) ?? 0),
            transform: HKTransform.decode(
                &cursor, at: transformOffset, named: "m_motion.m_motionState.m_transform"
            ),
            centerOfMassLocal: (cursor.vector4(at: centerOfMassField) ?? SIMD4()).xyz,
            inertiaAndMassInverse: cursor.vector4(at: inertiaField) ?? SIMD4(),
            linearDamping: HKHalf.value(cursor.uint16(at: linearDampingField) ?? 0),
            angularDamping: HKHalf.value(cursor.uint16(at: angularDampingField) ?? 0),
            gravityFactor: HKHalf.value(cursor.uint16(at: gravityFactorField) ?? 0),
            unresolved: cursor.unresolved
        )
    }

    /// Keyframed (4) or fixed (5): animation or nothing moves it, not forces.
    public var isDrivenOrFixed: Bool {
        motionType == 4 || motionType == 5
    }

    /// Zero for a body that never moves.
    public var mass: Float {
        inertiaAndMassInverse.w > 0 ? 1 / inertiaAndMassInverse.w : 0
    }

    public var references: [HKBReference] {
        HKBReference.optional("m_collidable.m_shape", shape)
    }

    public var summary: String {
        "\(name ?? "<unnamed>") mass \(mass), friction \(friction)"
    }
}

/// Decoded `hkpConstraintInstance`, size 112: a joint between two bodies, with
/// its data object.
nonisolated public struct HKPConstraintInstance: HKBClass, Equatable, Sendable {
    public let name: String?
    public let data: HKXPointerTarget?
    public let entityA: HKXPointerTarget?
    public let entityB: HKXPointerTarget?
    /// `hkpConstraintInstance::ConstraintPriority`.
    public let priority: Int
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkpConstraintInstance"

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKPConstraintInstance?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        return HKPConstraintInstance(
            name: cursor.string(at: HKXField(0x50, "m_name")),
            data: cursor.pointer(at: HKXField(0x18, "m_data")),
            entityA: cursor.pointer(at: HKXField(0x28, "m_entities[0]")),
            entityB: cursor.pointer(at: HKXField(0x30, "m_entities[1]")),
            priority: Int(cursor.uint8(at: HKXField(0x38, "m_priority")) ?? 0),
            unresolved: cursor.unresolved
        )
    }

    public var references: [HKBReference] {
        HKBReference.optional("m_data", data) + HKBReference.optional("m_entities[0]", entityA)
            + HKBReference.optional("m_entities[1]", entityB)
    }

    public var summary: String {
        name ?? "<unnamed constraint>"
    }
}
