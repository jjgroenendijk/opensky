// Gait speeds and angle math for the locomotion bridge, pure functions of their
// arguments. The one place OpenSky's yaw (counterclockwise from +X) becomes Havok's
// `Direction` (radians from facing, positive left).

import OpenSkyPhysics
import simd

nonisolated extension LocomotionBridge {
    /// Speed of one gait, units per second.
    public func speed(of gait: LocomotionGait) -> Float {
        switch gait {
        case .walk: configuration.walkSpeed.value
        case .run: configuration.runSpeed.value
        case .sprint: configuration.sprintSpeed.value
        case .sneak: configuration.sneakSpeed.value
        case .swim: configuration.swimSpeed.value
        }
    }

    /// This frame's intent as a level world-space movement direction, unit
    /// length or shorter. The yaw basis is OpenSky's own — forward is
    /// `(cos yaw, sin yaw)` and right is a quarter turn clockwise from it — so
    /// this is where a stick or a key pair becomes a world heading.
    public func intentDirection(yaw: Float) -> SIMD2<Float> {
        let forward = SIMD2<Float>(cosf(yaw), sinf(yaw))
        let right = SIMD2<Float>(sinf(yaw), -cosf(yaw))
        var direction = forward * intent.moveForward + right * intent.moveRight
        let magnitude = simd_length(direction)
        if magnitude > 1 {
            direction /= magnitude
        }
        return direction
    }

    /// Movement direction as the graph wants it: the fraction of a turn clockwise from
    /// facing, in [0, 1), so 0.25 is right. Zero when standing still. Source: the
    /// places of `MT_Direction_Blend` (docs/engine/locomotion-graph.md).
    public static func graphDirection(of direction: SIMD2<Float>, yaw: Float) -> Float {
        guard direction != SIMD2<Float>() else { return 0 }
        let left = shortestAngle(from: yaw, to: atan2f(direction.y, direction.x))
        let turn = -left / (2 * .pi)
        return turn < 0 ? turn + 1 : turn
    }

    /// Signed angle from one heading to another, in (-pi, pi].
    public static func shortestAngle(from start: Float, to end: Float) -> Float {
        var delta = (end - start).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi {
            delta -= 2 * .pi
        } else if delta <= -.pi {
            delta += 2 * .pi
        }
        return delta
    }
}
