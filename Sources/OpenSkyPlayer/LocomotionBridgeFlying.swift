// A flying mount's step: the flight rules move the dragon, so its graph only hears how
// it moves. See docs/engine/dragon-flight.md.

import OpenSkyBehavior
import simd

nonisolated extension LocomotionBridge {
    /// Writes the flight inputs and the measured motion, raises `events`, and steps the
    /// graph. The capsule does not move; `feet` is where the flight holds the body.
    public func advanceFlying(
        deltaTime: Float, feet: SIMD3<Float>, motion: MountMotion, events: [String],
        inputs: [(name: String, value: BehaviorVariableValue)]
    ) {
        updateStatus { status in
            status.feetPosition = feet
            status.lastPlan = .still
            status.verticalVelocity = 0
            status.isGrounded = true
        }
        guard deltaTime > 0 else { return }
        write(.real(motion.speed), to: LocomotionGraphNames.speed)
        write(.real(motion.turnDelta), to: LocomotionGraphNames.turnDelta)
        for (name, value) in inputs {
            write(value, to: name)
        }
        for event in events {
            raise(event)
        }
        if motion.isMoving != wasMoving {
            raise(motion.isMoving ? LocomotionGraphNames.moveStart : LocomotionGraphNames.moveStop)
        }
        _ = advanceGraph(deltaTime: deltaTime)
        wasMoving = motion.isMoving
        wasGrounded = true
    }
}
