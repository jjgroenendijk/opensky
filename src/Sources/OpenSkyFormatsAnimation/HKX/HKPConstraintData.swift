// The ragdoll joint data classes and their motor. Each is a list of constraint
// atoms, each atom starting with its `uint16` type. Offsets from HKX2Library
// (MIT). Byte map: docs/formats/hkx-physics.md.

import Foundation

/// The two joint frames every constraint data starts with
/// (`hkpSetLocalTransformsConstraintAtom` at 0x20): the pivot in each body's space.
nonisolated public struct HKPConstraintFrames: Equatable, Sendable {
    public let transformA: HKTransform
    public let transformB: HKTransform

    private static let member = "m_atoms.m_transforms"

    static func decode(_ cursor: inout HKXObjectCursor) -> HKPConstraintFrames {
        HKPConstraintFrames(
            transformA: HKTransform.decode(&cursor, at: 0x30, named: "\(member).m_transformA"),
            transformB: HKTransform.decode(&cursor, at: 0x70, named: "\(member).m_transformB")
        )
    }
}

/// An angle range in radians, and whether the solver applies it.
nonisolated public struct HKPAngleLimit: Equatable, Sendable {
    public let isEnabled: Bool
    public let minAngle: Float
    public let maxAngle: Float

    static func decode(
        _ cursor: inout HKXObjectCursor, enabledAt enabled: Int, minAt minimum: Int,
        named member: String
    ) -> HKPAngleLimit {
        HKPAngleLimit(
            isEnabled: (cursor.uint8(at: HKXField(enabled, "\(member).m_isEnabled")) ?? 0) != 0,
            minAngle: cursor.float32(at: HKXField(minimum, "\(member).m_minAngle")) ?? 0,
            maxAngle: cursor.float32(at: HKXField(minimum + 4, "\(member).m_maxAngle")) ?? 0
        )
    }
}

/// Decoded `hkpRagdollConstraintData`, size 384: a ball joint with a twist
/// limit, a cone limit, a plane limit, friction, and three motors.
nonisolated public struct HKPRagdollConstraintData: HKBClass, Equatable, Sendable {
    public let frames: HKPConstraintFrames
    public let motors: [HKXPointerTarget?]
    public let maxFrictionTorque: Float
    public let twistLimit: HKPAngleLimit
    public let coneLimit: HKPAngleLimit
    public let planesLimit: HKPAngleLimit
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkpRagdollConstraintData"

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKPRagdollConstraintData?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        let frames = HKPConstraintFrames.decode(&cursor)
        let motors = (0 ..< 3).map { index in
            cursor.optionalPointer(
                at: HKXField(0x100 + index * 8, "m_atoms.m_ragdollMotors.m_motors[\(index)]")
            )
        }
        return HKPRagdollConstraintData(
            frames: frames,
            motors: motors,
            maxFrictionTorque: cursor.float32(
                at: HKXField(0x128, "m_atoms.m_angFriction.m_maxFrictionTorque")
            ) ?? 0,
            twistLimit: HKPAngleLimit.decode(
                &cursor, enabledAt: 0x12E, minAt: 0x134, named: "m_atoms.m_twistLimit"
            ),
            coneLimit: HKPAngleLimit.decode(
                &cursor, enabledAt: 0x142, minAt: 0x148, named: "m_atoms.m_coneLimit"
            ),
            planesLimit: HKPAngleLimit.decode(
                &cursor, enabledAt: 0x156, minAt: 0x15C, named: "m_atoms.m_planesLimit"
            ),
            unresolved: cursor.unresolved
        )
    }

    public var references: [HKBReference] {
        HKBReference.each("m_atoms.m_ragdollMotors.m_motors", motors)
    }

    public var summary: String {
        "twist \(twistLimit.minAngle)...\(twistLimit.maxAngle), cone \(coneLimit.maxAngle)"
    }
}

/// Decoded `hkpLimitedHingeConstraintData`, size 272: a hinge with an angle
/// limit, friction, and one motor.
nonisolated public struct HKPLimitedHingeConstraintData: HKBClass, Equatable, Sendable {
    public let frames: HKPConstraintFrames
    public let motor: HKXPointerTarget?
    public let maxFrictionTorque: Float
    public let angleLimit: HKPAngleLimit
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkpLimitedHingeConstraintData"

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKPLimitedHingeConstraintData?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        return HKPLimitedHingeConstraintData(
            frames: HKPConstraintFrames.decode(&cursor),
            motor: cursor.optionalPointer(at: HKXField(0xD0, "m_atoms.m_angMotor.m_motor")),
            maxFrictionTorque: cursor.float32(
                at: HKXField(0xE0, "m_atoms.m_angFriction.m_maxFrictionTorque")
            ) ?? 0,
            angleLimit: HKPAngleLimit.decode(
                &cursor, enabledAt: 0xE6, minAt: 0xE8, named: "m_atoms.m_angLimit"
            ),
            unresolved: cursor.unresolved
        )
    }

    public var references: [HKBReference] {
        HKBReference.optional("m_atoms.m_angMotor.m_motor", motor)
    }

    public var summary: String {
        "hinge \(angleLimit.minAngle)...\(angleLimit.maxAngle)"
    }
}

/// Decoded `hkpPositionConstraintMotor`, size 48: a spring that pulls a joint
/// to its target angle.
nonisolated public struct HKPPositionConstraintMotor: HKBClass, Equatable, Sendable {
    public let minForce: Float
    public let maxForce: Float
    public let tau: Float
    public let damping: Float
    public let proportionalRecoveryVelocity: Float
    public let constantRecoveryVelocity: Float
    public let unresolved: [HKXUnresolvedReference]

    public static let className = "hkpPositionConstraintMotor"

    public static func decode(at target: HKXPointerTarget, in graph: HKXObjectGraph)
        -> HKPPositionConstraintMotor?
    {
        guard var cursor = graph.cursor(at: target) else { return nil }
        return HKPPositionConstraintMotor(
            minForce: cursor.float32(at: HKXField(0x18, "m_minForce")) ?? 0,
            maxForce: cursor.float32(at: HKXField(0x1C, "m_maxForce")) ?? 0,
            tau: cursor.float32(at: HKXField(0x20, "m_tau")) ?? 0,
            damping: cursor.float32(at: HKXField(0x24, "m_damping")) ?? 0,
            proportionalRecoveryVelocity: cursor.float32(
                at: HKXField(0x28, "m_proportionalRecoveryVelocity")
            ) ?? 0,
            constantRecoveryVelocity: cursor.float32(
                at: HKXField(0x2C, "m_constantRecoveryVelocity")
            ) ?? 0,
            unresolved: cursor.unresolved
        )
    }

    public var summary: String {
        "force \(minForce)...\(maxForce), tau \(tau), damping \(damping)"
    }
}
