// The seam between the locomotion bridge and the character controller. The state is the
// question (capsule, fall speed, ground, camera facing); the plan is the answer (horizontal
// move, takeoff, water). The plan carries displacement, not velocity, so nothing after it
// can integrate horizontal motion twice. Only the jump impulse writes vertical velocity.
// See docs/engine/walk-mode.md.

import OpenSkyPhysics
import OpenSkyWorldInterface
import simd

/// What the controller shows the planner before a fixed step runs.
nonisolated public struct LocomotionStepState: Equatable, Sendable {
    /// Capsule bottom, world units.
    public var feetPosition: SIMD3<Float>
    /// Signed vertical speed, units per second, positive up.
    public var verticalVelocity: Float
    /// Whether the previous step resolved onto walkable ground.
    public var isGrounded: Bool
    /// Level camera yaw, radians. Horizontal input is expressed against this.
    public var yaw: Float
    /// Length of the step about to run, seconds.
    public var dt: Float
}
