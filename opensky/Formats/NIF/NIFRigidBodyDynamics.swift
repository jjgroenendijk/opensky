// The inertial tail of a Skyrim rigid body: everything a dynamic simulation
// needs that the collision query path ignores. Layers above this one decide
// what to do with a motion system they do not support; the decoder reports
// the raw byte alongside the named case so an unknown value survives.
//
// Reference: NifTools nif.xml (bhkRigidBodyCInfo2010, hkMotionType,
// hkDeactivatorType, hkSolverDeactivation, hkQualityType, hkMatrix3).
//   https://github.com/niftools/nifxml/blob/develop/nif.xml
// Layout documented in docs/formats/nif-collision.md.

import Foundation
import simd

/// nif.xml `hkMotionType`. Decides whether item 15.2 integrates a body at all.
nonisolated enum NIFMotionSystem: UInt8, CaseIterable, Sendable {
    case invalid = 0
    case dynamic = 1
    case sphereInertia = 2
    case sphereStabilized = 3
    case boxInertia = 4
    case boxStabilized = 5
    case keyframed = 6
    case fixed = 7
    case thinBox = 8
    case character = 9

    /// True where the body is integrated from forces rather than driven by
    /// animation or nailed to the world.
    var isSimulated: Bool {
        switch self {
        case .dynamic, .sphereInertia, .sphereStabilized,
             .boxInertia, .boxStabilized, .thinBox:
            true
        case .invalid, .keyframed, .fixed, .character:
            false
        }
    }
}

/// nif.xml `hkQualityType`: collision priority the solver gives the body.
nonisolated enum NIFCollisionQuality: UInt8, CaseIterable, Sendable {
    case invalid = 0
    case fixed = 1
    case keyframed = 2
    case debris = 3
    case moving = 4
    case critical = 5
    case bullet = 6
    case user = 7
    case character = 8
    case keyframedReport = 9
}

/// nif.xml `hkDeactivatorType`.
nonisolated enum NIFDeactivatorType: UInt8, CaseIterable, Sendable {
    case invalid = 0
    case never = 1
    case spatial = 2
}

/// nif.xml `hkSolverDeactivation`.
nonisolated enum NIFSolverDeactivation: UInt8, CaseIterable, Sendable {
    case invalid = 0
    case off = 1
    case low = 2
    case medium = 3
    case high = 4
    case max = 5
}

/// The simulation-facing half of `bhkRigidBodyCInfo2010`.
///
/// Units are deliberately mixed and each field says which it is. Positions
/// (`centerOfMass`) convert to engine units like every other Havok position in
/// this format layer. Masses, inertia, damping, and the velocity ceilings stay
/// in the Havok SI units the file stores, because the integrator in item 15.2
/// picks its own working units and a half-converted body would be worse than
/// an unconverted one.
nonisolated struct NIFRigidBodyDynamics: Sendable {
    /// Kilograms. Zero means immovable even where the motion system is dynamic.
    let mass: Float
    /// kg m^2, symmetric. nif.xml stores 3x4 rows with an unused fourth
    /// column; read as rows and transposed here so it applies to column
    /// vectors, the same convention as `NIFObjectPrefix.rotation`.
    let inertiaTensor: float3x3
    /// Engine units, body-local.
    let centerOfMass: SIMD3<Float>
    /// Metres per second, body-local. Vanilla static geometry stores zero.
    let linearVelocity: SIMD3<Float>
    /// Radians per second.
    let angularVelocity: SIMD3<Float>
    /// Fraction of linear velocity removed per second.
    let linearDamping: Float
    /// Fraction of angular velocity removed per second.
    let angularDamping: Float
    let timeFactor: Float
    let gravityFactor: Float
    let friction: Float
    let rollingFrictionMultiplier: Float
    let restitution: Float
    /// Metres per second.
    let maxLinearVelocity: Float
    /// Radians per second.
    let maxAngularVelocity: Float
    /// Metres of penetration the solver is allowed to tolerate.
    let penetrationDepth: Float
    /// Raw `hkMotionType` byte; `motionSystem` names it where the value is known.
    let rawMotionSystem: UInt8
    let rawDeactivatorType: UInt8
    let rawSolverDeactivation: UInt8
    let rawQualityType: UInt8

    var motionSystem: NIFMotionSystem? {
        NIFMotionSystem(rawValue: rawMotionSystem)
    }

    var deactivatorType: NIFDeactivatorType? {
        NIFDeactivatorType(rawValue: rawDeactivatorType)
    }

    var solverDeactivation: NIFSolverDeactivation? {
        NIFSolverDeactivation(rawValue: rawSolverDeactivation)
    }

    var qualityType: NIFCollisionQuality? {
        NIFCollisionQuality(rawValue: rawQualityType)
    }

    /// A body item 15.2 should integrate: a known simulated motion system with
    /// a positive finite mass. An unknown motion byte is not simulated, so a
    /// modded or future value degrades to static rather than to nonsense.
    var isSimulated: Bool {
        (motionSystem?.isSimulated ?? false) && mass > 0 && mass.isFinite
    }
}
