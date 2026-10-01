// The seam between the locomotion bridge and the character controller. The state is the
// question (capsule, fall speed, ground, camera facing); the plan is the answer (horizontal
// move, takeoff, water). The plan carries displacement, not velocity, so nothing after it
// can integrate horizontal motion twice. Only the jump impulse writes vertical velocity.
// See docs/engine/walk-mode.md.

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

/// Where one fixed step's horizontal displacement came from. Reported rather
/// than assumed: vanilla locomotion clips carry no extracted motion, so the
/// vanilla answer is always `configuredSpeed`, and a data set that does carry
/// root motion has to be visible as such instead of looking identical.
nonisolated public enum LocomotionMotionSource: Equatable, Sendable {
    /// The behavior graph's own root travel drove the step.
    case rootMotion
    /// The resolved gait speed drove the step, with the graph as a consumer of
    /// the movement variables rather than the source of the movement.
    case configuredSpeed
    /// Nothing asked for horizontal motion this step.
    case idle
}

/// What the planner asks of one fixed step.
nonisolated public struct LocomotionStepPlan: Equatable, Sendable {
    /// World-space horizontal displacement wanted this step, world units. The
    /// only horizontal quantity in the system; the controller turns it into a
    /// collide-and-slide move and never scales it by time again.
    public var horizontalDisplacement = SIMD2<Float>()
    /// Upward velocity injected once, this step only, or nil for no takeoff.
    public var jumpImpulse: Float?
    /// Water surface height at the capsule, when the step happens submerged
    /// deeply enough to swim. Nil on land.
    public var swimSurfaceHeight: Float?
    /// Vertical speed the swimmer is asking for, units per second, positive up.
    /// Ignored out of water.
    public var swimVerticalVelocity: Float = 0
    /// Where `horizontalDisplacement` came from, for readouts and tests.
    public var motionSource: LocomotionMotionSource = .idle

    public var isSwimming: Bool {
        swimSurfaceHeight != nil
    }

    /// A step that asks for nothing. What a paused frame plans, and what a
    /// controller with no planner behaves as.
    public static let still = LocomotionStepPlan()
}
