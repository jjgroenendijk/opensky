// The inertial tail of a Skyrim rigid body. Each enum keeps its raw byte, so
// an unknown value survives. Layout: docs/formats/nif-rigid-body.md.

import Foundation
import simd

/// nif.xml `hkMotionType`. Decides whether physics integrates a body at all.
nonisolated public enum NIFMotionSystem: UInt8, CaseIterable, Sendable {
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
    public var isSimulated: Bool {
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
nonisolated public enum NIFCollisionQuality: UInt8, CaseIterable, Sendable {
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
nonisolated public enum NIFDeactivatorType: UInt8, CaseIterable, Sendable {
    case invalid = 0
    case never = 1
    case spatial = 2
}

/// nif.xml `hkSolverDeactivation`.
nonisolated public enum NIFSolverDeactivation: UInt8, CaseIterable, Sendable {
    case invalid = 0
    case off = 1
    case low = 2
    case medium = 3
    case high = 4
    case max = 5
}

/// The simulation half of `bhkRigidBodyCInfo2010`. `centerOfMass` is in engine
/// units; mass, inertia, damping, and velocity limits stay in Havok SI units,
/// because the physics step picks its own units.
nonisolated public struct NIFRigidBodyDynamics: Sendable {
    /// Kilograms. Zero means immovable even where the motion system is dynamic.
    public let mass: Float
    /// kg m^2, symmetric. nif.xml stores 3x4 rows with an unused fourth
    /// column; read as rows and transposed here so it applies to column
    /// vectors, the same convention as `NIFObjectPrefix.rotation`.
    public let inertiaTensor: float3x3
    /// Engine units, body-local.
    public let centerOfMass: SIMD3<Float>
    /// Metres per second, body-local. Vanilla static geometry stores zero.
    public let linearVelocity: SIMD3<Float>
    /// Radians per second.
    public let angularVelocity: SIMD3<Float>
    /// Fraction of linear velocity removed per second.
    public let linearDamping: Float
    /// Fraction of angular velocity removed per second.
    public let angularDamping: Float
    public let timeFactor: Float
    public let gravityFactor: Float
    public let friction: Float
    public let rollingFrictionMultiplier: Float
    public let restitution: Float
    /// Metres per second.
    public let maxLinearVelocity: Float
    /// Radians per second.
    public let maxAngularVelocity: Float
    /// Metres of penetration the solver is allowed to tolerate.
    public let penetrationDepth: Float
    /// Raw `hkMotionType` byte; `motionSystem` names it where the value is known.
    public let rawMotionSystem: UInt8
    public let rawDeactivatorType: UInt8
    public let rawSolverDeactivation: UInt8
    public let rawQualityType: UInt8

    public var motionSystem: NIFMotionSystem? {
        NIFMotionSystem(rawValue: rawMotionSystem)
    }

    public var deactivatorType: NIFDeactivatorType? {
        NIFDeactivatorType(rawValue: rawDeactivatorType)
    }

    public var solverDeactivation: NIFSolverDeactivation? {
        NIFSolverDeactivation(rawValue: rawSolverDeactivation)
    }

    public var qualityType: NIFCollisionQuality? {
        NIFCollisionQuality(rawValue: rawQualityType)
    }

    /// A body physics should integrate: a known simulated motion system with
    /// a positive finite mass. An unknown motion byte is not simulated, so a
    /// modded or future value degrades to static rather than to nonsense.
    public var isSimulated: Bool {
        (motionSystem?.isSimulated ?? false) && mass > 0 && mass.isFinite
    }
}
