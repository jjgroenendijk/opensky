import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import simd

/// Where one reference is and how it moves. Angles are radians, as placements store them.
nonisolated public struct ReferenceMotionFacts: Equatable, Sendable {
    public var position: SIMD3<Float>
    public var rotation: SIMD3<Float>
    /// World units per second.
    public var velocity: SIMD3<Float>
    /// The next waypoint of the path the actor follows, nil when it follows none.
    public var pathTarget: SIMD3<Float>?
    /// The speed its path gait asks for, world units per second.
    public var pathTargetSpeed: Float
    /// The fastest it turns toward its path, radians per second.
    public var pathTurnSpeed: Float

    public init(
        position: SIMD3<Float>,
        rotation: SIMD3<Float> = .zero,
        velocity: SIMD3<Float> = .zero,
        pathTarget: SIMD3<Float>? = nil,
        pathTargetSpeed: Float = 0,
        pathTurnSpeed: Float = 0
    ) {
        self.position = position
        self.rotation = rotation
        self.velocity = velocity
        self.pathTarget = pathTarget
        self.pathTargetSpeed = pathTargetSpeed
        self.pathTurnSpeed = pathTurnSpeed
    }

    /// Below this a body counts as standing, in world units per second.
    static let movingThreshold: Float = 1

    package var speed: Float {
        simd_length(SIMD2(velocity.x, velocity.y))
    }

    /// Degrees from this heading to `point`, in -180...180. Heading 0 faces +Y and
    /// grows clockwise, as a placement's Z rotation does.
    package func headingAngle(to point: SIMD3<Float>) -> Float {
        let delta = point - position
        let bearing = atan2(delta.x, delta.y)
        return Self.wrappedDegrees(bearing - rotation.z)
    }

    /// Degrees per second about Z: the turn rate while the path is off its heading.
    package func pathTurnRate(current: Bool) -> Float {
        guard let pathTarget else { return 0 }
        if current, abs(headingAngle(to: pathTarget)) < 1 {
            return 0
        }
        return pathTurnSpeed * 180 / .pi
    }

    /// 0 standing, 1 forward, 2 right, 3 back, 4 left.
    package var movementDirection: Float {
        guard speed >= Self.movingThreshold else { return 0 }
        let angle = Self.wrappedDegrees(atan2(velocity.x, velocity.y) - rotation.z)
        return switch angle {
        case -45 ..< 45: 1
        case 45 ..< 135: 2
        case -135 ..< -45: 4
        default: 3
        }
    }

    /// Rounded to a thousandth, so a right angle compares equal to 90.
    static func wrappedDegrees(_ radians: Float) -> Float {
        var degrees = (radians * 180 / .pi * 1000).rounded() / 1000
        degrees = degrees.truncatingRemainder(dividingBy: 360)
        if degrees > 180 {
            degrees -= 360
        }
        if degrees < -180 {
            degrees += 360
        }
        return degrees
    }
}
