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
nonisolated enum NIFConstraintType: UInt32, CaseIterable, Sendable {
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
nonisolated struct NIFPositionMotor: Sendable {
    let minForce: Float
    let maxForce: Float
    let tau: Float
    let damping: Float
    let proportionalRecoveryVelocity: Float
    let constantRecoveryVelocity: Float
    let isEnabled: Bool
}

/// nif.xml `bhkVelocityConstraintMotor`.
nonisolated struct NIFVelocityMotor: Sendable {
    let minForce: Float
    let maxForce: Float
    let tau: Float
    let targetVelocity: Float
    let usesVelocityTarget: Bool
    let isEnabled: Bool
}

/// nif.xml `bhkSpringDamperConstraintMotor`.
nonisolated struct NIFSpringDamperMotor: Sendable {
    let minForce: Float
    let maxForce: Float
    let springConstant: Float
    let springDamping: Float
    let isEnabled: Bool
}

/// nif.xml `bhkConstraintMotorCInfo`. The stored type byte selects which
/// payload follows, and `MOTOR_NONE` stores no payload at all.
nonisolated enum NIFConstraintMotor: Sendable {
    case none
    case position(NIFPositionMotor)
    case velocity(NIFVelocityMotor)
    case springDamper(NIFSpringDamperMotor)

    var isEnabled: Bool {
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
nonisolated struct NIFConstraintHingeFrame: Sendable {
    let axis: SIMD3<Float>
    let perpAxis1: SIMD3<Float>
    let perpAxis2: SIMD3<Float>
    let pivot: SIMD3<Float>
}

/// One body's end of a ragdoll constraint. `twist` is the cone's central axis,
/// `plane` the orthogonal plane normal, `motor` the third orthogonal
/// direction; all three are unit vectors and `pivot` is in engine units.
nonisolated struct NIFConstraintRagdollFrame: Sendable {
    let twist: SIMD3<Float>
    let plane: SIMD3<Float>
    let motor: SIMD3<Float>
    let pivot: SIMD3<Float>
}

/// One body's end of a prismatic (rail) constraint.
nonisolated struct NIFConstraintPrismaticFrame: Sendable {
    let sliding: SIMD3<Float>
    let rotation: SIMD3<Float>
    let plane: SIMD3<Float>
    let pivot: SIMD3<Float>
}

/// Three degrees of freedom bounded by a cone plus two orthogonal cones. The
/// joint every vanilla ragdoll bone pair uses. Cone minimum angle is not
/// stored: nif.xml records it as the negation of `coneMaxAngle`.
nonisolated struct NIFRagdollConstraint: Sendable {
    let frameA: NIFConstraintRagdollFrame
    let frameB: NIFConstraintRagdollFrame
    let coneMaxAngle: Float
    let planeMinAngle: Float
    let planeMaxAngle: Float
    let twistMinAngle: Float
    let twistMaxAngle: Float
    let maxFriction: Float
    let motor: NIFConstraintMotor
}

/// One rotation axis, unbounded and unmotorized.
nonisolated struct NIFHingeConstraint: Sendable {
    let frameA: NIFConstraintHingeFrame
    let frameB: NIFConstraintHingeFrame
}

/// One rotation axis bounded by `minAngle`/`maxAngle` radians, optionally
/// motorized.
nonisolated struct NIFLimitedHingeConstraint: Sendable {
    let frameA: NIFConstraintHingeFrame
    let frameB: NIFConstraintHingeFrame
    let minAngle: Float
    let maxAngle: Float
    let maxFriction: Float
    let motor: NIFConstraintMotor
}

/// Translation along one axis between `minDistance` and `maxDistance` engine
/// units, all rotation fixed.
nonisolated struct NIFPrismaticConstraint: Sendable {
    let frameA: NIFConstraintPrismaticFrame
    let frameB: NIFConstraintPrismaticFrame
    let minDistance: Float
    let maxDistance: Float
    let friction: Float
    let motor: NIFConstraintMotor
}

/// Point-to-point: hold both pivots at the same place, rotation free.
nonisolated struct NIFBallAndSocketConstraint: Sendable {
    let pivotA: SIMD3<Float>
    let pivotB: SIMD3<Float>
}

/// Hold both pivots `length` engine units apart.
nonisolated struct NIFStiffSpringConstraint: Sendable {
    let pivotA: SIMD3<Float>
    let pivotB: SIMD3<Float>
    let length: Float
}

/// The decoded joint. `malleable` wraps another joint and softens it, so the
/// enum is recursive.
indirect nonisolated enum NIFConstraintData: Sendable {
    case ballAndSocket(NIFBallAndSocketConstraint)
    case hinge(NIFHingeConstraint)
    case limitedHinge(NIFLimitedHingeConstraint)
    case prismatic(NIFPrismaticConstraint)
    case ragdoll(NIFRagdollConstraint)
    case stiffSpring(NIFStiffSpringConstraint)
    case malleable(strength: Float, wrapped: NIFConstraintData)

    /// The joint under any number of malleable wrappers.
    var unwrapped: NIFConstraintData {
        guard case let .malleable(_, wrapped) = self else { return self }
        return wrapped.unwrapped
    }

    var type: NIFConstraintType {
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
nonisolated struct NIFCollisionConstraint: Sendable {
    /// Block index of the constraint itself, so a constraint reached from both
    /// of its bodies is counted once.
    let block: Int
    let entityA: Int32
    let entityB: Int32
    /// nif.xml `ConstraintPriority`: 1 = solved at physics steps, 3 = also at
    /// time of impact.
    let priority: UInt32
    let data: NIFConstraintData

    var type: NIFConstraintType {
        data.type
    }
}
