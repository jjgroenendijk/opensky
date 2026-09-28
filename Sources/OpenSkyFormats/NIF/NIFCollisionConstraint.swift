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
nonisolated package enum NIFConstraintType: UInt32, CaseIterable, Sendable {
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
nonisolated package struct NIFPositionMotor: Sendable {
    package let minForce: Float
    package let maxForce: Float
    package let tau: Float
    package let damping: Float
    package let proportionalRecoveryVelocity: Float
    package let constantRecoveryVelocity: Float
    package let isEnabled: Bool
}

/// nif.xml `bhkVelocityConstraintMotor`.
nonisolated package struct NIFVelocityMotor: Sendable {
    package let minForce: Float
    package let maxForce: Float
    package let tau: Float
    package let targetVelocity: Float
    package let usesVelocityTarget: Bool
    package let isEnabled: Bool
}

/// nif.xml `bhkSpringDamperConstraintMotor`.
nonisolated package struct NIFSpringDamperMotor: Sendable {
    package let minForce: Float
    package let maxForce: Float
    package let springConstant: Float
    package let springDamping: Float
    package let isEnabled: Bool
}

/// nif.xml `bhkConstraintMotorCInfo`. The stored type byte selects which
/// payload follows, and `MOTOR_NONE` stores no payload at all.
nonisolated package enum NIFConstraintMotor: Sendable {
    case none
    case position(NIFPositionMotor)
    case velocity(NIFVelocityMotor)
    case springDamper(NIFSpringDamperMotor)

    package var isEnabled: Bool {
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
nonisolated package struct NIFConstraintHingeFrame: Sendable {
    package let axis: SIMD3<Float>
    package let perpAxis1: SIMD3<Float>
    package let perpAxis2: SIMD3<Float>
    package let pivot: SIMD3<Float>
}

/// One body's end of a ragdoll constraint. `twist` is the cone's central axis,
/// `plane` the orthogonal plane normal, `motor` the third orthogonal
/// direction; all three are unit vectors and `pivot` is in engine units.
nonisolated package struct NIFConstraintRagdollFrame: Sendable {
    package let twist: SIMD3<Float>
    package let plane: SIMD3<Float>
    package let motor: SIMD3<Float>
    package let pivot: SIMD3<Float>
}

/// One body's end of a prismatic (rail) constraint.
nonisolated package struct NIFConstraintPrismaticFrame: Sendable {
    package let sliding: SIMD3<Float>
    package let rotation: SIMD3<Float>
    package let plane: SIMD3<Float>
    package let pivot: SIMD3<Float>
}

/// Three degrees of freedom bounded by a cone plus two orthogonal cones. The
/// joint every vanilla ragdoll bone pair uses. Cone minimum angle is not
/// stored: nif.xml records it as the negation of `coneMaxAngle`.
nonisolated package struct NIFRagdollConstraint: Sendable {
    package let frameA: NIFConstraintRagdollFrame
    package let frameB: NIFConstraintRagdollFrame
    package let coneMaxAngle: Float
    package let planeMinAngle: Float
    package let planeMaxAngle: Float
    package let twistMinAngle: Float
    package let twistMaxAngle: Float
    package let maxFriction: Float
    package let motor: NIFConstraintMotor
}

/// One rotation axis, unbounded and unmotorized.
nonisolated package struct NIFHingeConstraint: Sendable {
    package let frameA: NIFConstraintHingeFrame
    package let frameB: NIFConstraintHingeFrame
}

/// One rotation axis bounded by `minAngle`/`maxAngle` radians, optionally
/// motorized.
nonisolated package struct NIFLimitedHingeConstraint: Sendable {
    package let frameA: NIFConstraintHingeFrame
    package let frameB: NIFConstraintHingeFrame
    package let minAngle: Float
    package let maxAngle: Float
    package let maxFriction: Float
    package let motor: NIFConstraintMotor
}

/// Translation along one axis between `minDistance` and `maxDistance` engine
/// units, all rotation fixed.
nonisolated package struct NIFPrismaticConstraint: Sendable {
    package let frameA: NIFConstraintPrismaticFrame
    package let frameB: NIFConstraintPrismaticFrame
    package let minDistance: Float
    package let maxDistance: Float
    package let friction: Float
    package let motor: NIFConstraintMotor
}

/// Point-to-point: hold both pivots at the same place, rotation free.
nonisolated package struct NIFBallAndSocketConstraint: Sendable {
    package let pivotA: SIMD3<Float>
    package let pivotB: SIMD3<Float>
}

/// Hold both pivots `length` engine units apart.
nonisolated package struct NIFStiffSpringConstraint: Sendable {
    package let pivotA: SIMD3<Float>
    package let pivotB: SIMD3<Float>
    package let length: Float
}

/// The decoded joint. `malleable` wraps another joint and softens it, so the
/// enum is recursive.
indirect nonisolated package enum NIFConstraintData: Sendable {
    case ballAndSocket(NIFBallAndSocketConstraint)
    case hinge(NIFHingeConstraint)
    case limitedHinge(NIFLimitedHingeConstraint)
    case prismatic(NIFPrismaticConstraint)
    case ragdoll(NIFRagdollConstraint)
    case stiffSpring(NIFStiffSpringConstraint)
    case malleable(strength: Float, wrapped: NIFConstraintData)

    /// The joint under any number of malleable wrappers.
    package var unwrapped: NIFConstraintData {
        guard case let .malleable(_, wrapped) = self else { return self }
        return wrapped.unwrapped
    }

    package var type: NIFConstraintType {
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
nonisolated package struct NIFCollisionConstraint: Sendable {
    /// Block index of the constraint itself, so a constraint reached from both
    /// of its bodies is counted once.
    package let block: Int
    package let entityA: Int32
    package let entityB: Int32
    /// nif.xml `ConstraintPriority`: 1 = solved at physics steps, 3 = also at
    /// time of impact.
    package let priority: UInt32
    package let data: NIFConstraintData

    package var type: NIFConstraintType {
        data.type
    }
}
