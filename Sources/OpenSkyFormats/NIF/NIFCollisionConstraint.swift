// Engine-facing Havok constraint values. A constraint joins two rigid bodies;
// the ragdoll on a character skeleton is a graph of them. Pivots arrive in
// engine units, axes stay unit-length and unitless, angles stay radians.
//
// Reference: NifTools nif.xml (bhkConstraint, bhkConstraintCInfo,
// bhkRagdollConstraintCInfo, bhkHingeConstraintCInfo,
// bhkLimitedHingeConstraintCInfo, bhkBallAndSocketConstraintCInfo,
// bhkStiffSpringConstraintCInfo, bhkPrismaticConstraintCInfo,
// bhkConstraintMotorCInfo, hkConstraintType, hkMotorType).
//   https://github.com/niftools/nifxml/blob/develop/nif.xml
// Layout documented in docs/formats/nif-collision.md.

import Foundation
import simd

/// nif.xml `hkConstraintType`. Values 3-5 and 9-12 are unused by the format.
nonisolated public enum NIFConstraintType: UInt32, CaseIterable, Sendable {
    case ballAndSocket = 0
    case hinge = 1
    case limitedHinge = 2
    case prismatic = 6
    case ragdoll = 7
    case stiffSpring = 8
    case malleable = 13
}

/// nif.xml `bhkPositionConstraintMotor`: drives towards a target angle. This
/// is the motor a posed ragdoll uses.
nonisolated public struct NIFPositionMotor: Sendable {
    public let minForce: Float
    public let maxForce: Float
    public let tau: Float
    public let damping: Float
    public let proportionalRecoveryVelocity: Float
    public let constantRecoveryVelocity: Float
    public let isEnabled: Bool
}

/// nif.xml `bhkVelocityConstraintMotor`.
nonisolated public struct NIFVelocityMotor: Sendable {
    public let minForce: Float
    public let maxForce: Float
    public let tau: Float
    public let targetVelocity: Float
    public let usesVelocityTarget: Bool
    public let isEnabled: Bool
}

/// nif.xml `bhkSpringDamperConstraintMotor`.
nonisolated public struct NIFSpringDamperMotor: Sendable {
    public let minForce: Float
    public let maxForce: Float
    public let springConstant: Float
    public let springDamping: Float
    public let isEnabled: Bool
}

/// nif.xml `bhkConstraintMotorCInfo`. The stored type byte selects which
/// payload follows, and `MOTOR_NONE` stores no payload at all.
nonisolated public enum NIFConstraintMotor: Sendable {
    case none
    case position(NIFPositionMotor)
    case velocity(NIFVelocityMotor)
    case springDamper(NIFSpringDamperMotor)

    public var isEnabled: Bool {
        switch self {
        case .none: false
        case let .position(motor): motor.isEnabled
        case let .velocity(motor): motor.isEnabled
        case let .springDamper(motor): motor.isEnabled
        }
    }
}

/// One body's end of a hinge-family constraint: the rotation axis, the two
/// in-plane reference axes, and the pivot. `axis` and both perpendicular axes
/// are unit vectors; `pivot` is in engine units, body-local.
nonisolated public struct NIFConstraintHingeFrame: Sendable {
    public let axis: SIMD3<Float>
    public let perpAxis1: SIMD3<Float>
    public let perpAxis2: SIMD3<Float>
    public let pivot: SIMD3<Float>
}

/// One body's end of a ragdoll constraint. `twist` is the cone's central axis,
/// `plane` the orthogonal plane normal, `motor` the third orthogonal
/// direction; all three are unit vectors and `pivot` is in engine units.
nonisolated public struct NIFConstraintRagdollFrame: Sendable {
    public let twist: SIMD3<Float>
    public let plane: SIMD3<Float>
    public let motor: SIMD3<Float>
    public let pivot: SIMD3<Float>
}

/// One body's end of a prismatic (rail) constraint.
nonisolated public struct NIFConstraintPrismaticFrame: Sendable {
    public let sliding: SIMD3<Float>
    public let rotation: SIMD3<Float>
    public let plane: SIMD3<Float>
    public let pivot: SIMD3<Float>
}

/// Three degrees of freedom bounded by a cone plus two orthogonal cones. The
/// joint every vanilla ragdoll bone pair uses. Cone minimum angle is not
/// stored: nif.xml records it as the negation of `coneMaxAngle`.
nonisolated public struct NIFRagdollConstraint: Sendable {
    public let frameA: NIFConstraintRagdollFrame
    public let frameB: NIFConstraintRagdollFrame
    public let coneMaxAngle: Float
    public let planeMinAngle: Float
    public let planeMaxAngle: Float
    public let twistMinAngle: Float
    public let twistMaxAngle: Float
    public let maxFriction: Float
    public let motor: NIFConstraintMotor
}

/// One rotation axis, unbounded and unmotorized.
nonisolated public struct NIFHingeConstraint: Sendable {
    public let frameA: NIFConstraintHingeFrame
    public let frameB: NIFConstraintHingeFrame
}

/// One rotation axis bounded by `minAngle`/`maxAngle` radians, optionally
/// motorized.
nonisolated public struct NIFLimitedHingeConstraint: Sendable {
    public let frameA: NIFConstraintHingeFrame
    public let frameB: NIFConstraintHingeFrame
    public let minAngle: Float
    public let maxAngle: Float
    public let maxFriction: Float
    public let motor: NIFConstraintMotor
}

/// Translation along one axis between `minDistance` and `maxDistance` engine
/// units, all rotation fixed.
nonisolated public struct NIFPrismaticConstraint: Sendable {
    public let frameA: NIFConstraintPrismaticFrame
    public let frameB: NIFConstraintPrismaticFrame
    public let minDistance: Float
    public let maxDistance: Float
    public let friction: Float
    public let motor: NIFConstraintMotor
}

/// Point-to-point: hold both pivots at the same place, rotation free.
nonisolated public struct NIFBallAndSocketConstraint: Sendable {
    public let pivotA: SIMD3<Float>
    public let pivotB: SIMD3<Float>
}

/// Hold both pivots `length` engine units apart.
nonisolated public struct NIFStiffSpringConstraint: Sendable {
    public let pivotA: SIMD3<Float>
    public let pivotB: SIMD3<Float>
    public let length: Float
}

/// The decoded joint. `malleable` wraps another joint and softens it, so the
/// enum is recursive.
indirect nonisolated public enum NIFConstraintData: Sendable {
    case ballAndSocket(NIFBallAndSocketConstraint)
    case hinge(NIFHingeConstraint)
    case limitedHinge(NIFLimitedHingeConstraint)
    case prismatic(NIFPrismaticConstraint)
    case ragdoll(NIFRagdollConstraint)
    case stiffSpring(NIFStiffSpringConstraint)
    case malleable(strength: Float, wrapped: NIFConstraintData)

    /// The joint under any number of malleable wrappers.
    public var unwrapped: NIFConstraintData {
        guard case let .malleable(_, wrapped) = self else { return self }
        return wrapped.unwrapped
    }

    public var type: NIFConstraintType {
        switch self {
        case .ballAndSocket: .ballAndSocket
        case .hinge: .hinge
        case .limitedHinge: .limitedHinge
        case .prismatic: .prismatic
        case .ragdoll: .ragdoll
        case .stiffSpring: .stiffSpring
        case .malleable: .malleable
        }
    }
}

/// A joint plus the two bodies it binds. `entityA`/`entityB` are `Ptr` block
/// indices into the same NIF, or -1 where the file leaves an end unbound;
/// `NIFCollisionModel.constraintBoneNames` turns them into skeleton bone
/// names.
nonisolated public struct NIFCollisionConstraint: Sendable {
    /// Block index of the constraint itself, so a constraint reached from both
    /// of its bodies is counted once.
    public let block: Int
    public let entityA: Int32
    public let entityB: Int32
    /// nif.xml `ConstraintPriority`: 1 = solved at physics steps, 3 = also at
    /// time of impact.
    public let priority: UInt32
    public let data: NIFConstraintData

    public var type: NIFConstraintType {
        data.type
    }
}
