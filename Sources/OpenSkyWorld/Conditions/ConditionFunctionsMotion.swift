// Position and movement condition functions, indices from xEdit wbDefinitionsTES5.pas:
// 6 GetPos, 25 IsMoving, 99 GetHeadingAngle, 446 GetVelocity, 584 GetRelativeAngle, 589
// GetMovementDirection, 620-623 and 683-684 the pathing reads, 639 GetWithinDistance,
// 680 GetActivatorHeight, 704 IsPathing, 720 GetTargetHeight.
// See docs/engine/condition-functions-world.md#motion.

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

    var speed: Float {
        simd_length(SIMD2(velocity.x, velocity.y))
    }

    /// `ptAxis` stores the letter: 88 X, 89 Y, 90 Z.
    static func axisIndex(_ parameter: Condition.Parameter?) -> Int? {
        switch parameter?.asInt32 {
        case 88: 0
        case 89: 1
        case 90: 2
        default: nil
        }
    }

    /// Degrees from this heading to `point`, in -180...180. Heading 0 faces +Y and
    /// grows clockwise, as a placement's Z rotation does.
    func headingAngle(to point: SIMD3<Float>) -> Float {
        let delta = point - position
        let bearing = atan2(delta.x, delta.y)
        return Self.wrappedDegrees(bearing - rotation.z)
    }

    /// Degrees per second about Z: the turn rate while the path is off its heading.
    func pathTurnRate(current: Bool) -> Float {
        guard let pathTarget else { return 0 }
        if current, abs(headingAngle(to: pathTarget)) < 1 {
            return 0
        }
        return pathTurnSpeed * 180 / .pi
    }

    /// 0 standing, 1 forward, 2 right, 3 back, 4 left.
    var movementDirection: Float {
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

nonisolated public struct MotionConditionResolution: ConditionResolution, Sendable {
    public static let empty = MotionConditionResolution(facts: nil)

    private let facts: [ReferenceKey: ReferenceMotionFacts]?

    public init(facts: [ReferenceKey: ReferenceMotionFacts]?) {
        self.facts = facts
    }

    public func facts(of key: ReferenceKey) -> ReferenceMotionFacts? {
        facts?[key]
    }
}

nonisolated extension ConditionContext {
    public var motion: MotionConditionResolution {
        get { self[resolution: MotionConditionResolution.self] }
        set { self[resolution: MotionConditionResolution.self] = newValue }
    }
}
