// Gait speeds and the angle math the locomotion bridge resolves with, split
// out of LocomotionBridge.swift for the strict-lint type-body cap.
//
// Everything here is a pure function of its arguments and the resolved movement
// configuration: no edge state, no graph, no capsule. That is what makes the
// direction convention below testable on its own, which matters because it is
// the one place OpenSky's yaw convention (counterclockwise from +X) is
// translated into the one Havok's `Direction` variable uses (radians away from
// facing, positive to the left).

import simd

nonisolated extension LocomotionBridge {
    /// Speed of one gait, units per second.
    func speed(of gait: LocomotionGait) -> Float {
        switch gait {
        case .walk: configuration.walkSpeed.value
        case .run: configuration.runSpeed.value
        case .sprint: configuration.sprintSpeed.value
        case .sneak: configuration.sneakSpeed.value
        case .swim: configuration.swimSpeed.value
        }
    }

    /// Movement direction as the graph wants it: radians away from facing,
    /// positive to the left, zero straight ahead, and zero when standing still.
    static func graphDirection(of direction: SIMD2<Float>, yaw: Float) -> Float {
        guard direction != SIMD2<Float>() else { return 0 }
        return shortestAngle(from: yaw, to: atan2f(direction.y, direction.x))
    }

    /// Signed angle from one heading to another, in (-pi, pi].
    static func shortestAngle(from start: Float, to end: Float) -> Float {
        var delta = (end - start).truncatingRemainder(dividingBy: 2 * .pi)
        if delta > .pi {
            delta -= 2 * .pi
        } else if delta <= -.pi {
            delta += 2 * .pi
        }
        return delta
    }
}
