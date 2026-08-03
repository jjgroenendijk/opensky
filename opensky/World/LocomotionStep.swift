// The seam between the locomotion bridge and the character controller
// (issue #188).
//
// One fixed step of walk mode is a question and an answer. `LocomotionStepState`
// is the question: where the capsule is, how fast it is falling, whether it is
// on the ground, and which way the camera faces. `LocomotionStepPlan` is the
// answer: how far to move horizontally, whether to take off, and whether the
// step happens in water.
//
// Keeping the two as plain values is what makes the movement-authority rule
// checkable rather than aspirational. The plan carries a horizontal
// displacement and no horizontal velocity, so nothing downstream of it can
// integrate horizontal motion a second time; the controller carries vertical
// velocity and the plan cannot write it except through the one-shot jump
// impulse. See docs/engine/walk-mode.md.

import simd

/// What the controller shows the planner before a fixed step runs.
nonisolated struct LocomotionStepState: Equatable, Sendable {
    /// Capsule bottom, world units.
    var feetPosition: SIMD3<Float>
    /// Signed vertical speed, units per second, positive up.
    var verticalVelocity: Float
    /// Whether the previous step resolved onto walkable ground.
    var isGrounded: Bool
    /// Level camera yaw, radians. Horizontal input is expressed against this.
    var yaw: Float
    /// Length of the step about to run, seconds.
    var dt: Float
}

/// Where one fixed step's horizontal displacement came from. Reported rather
/// than assumed: vanilla locomotion clips carry no extracted motion, so the
/// vanilla answer is always `configuredSpeed`, and a data set that does carry
/// root motion has to be visible as such instead of looking identical.
nonisolated enum LocomotionMotionSource: Equatable, Sendable {
    /// The behavior graph's own root travel drove the step.
    case rootMotion
    /// The resolved gait speed drove the step, with the graph as a consumer of
    /// the movement variables rather than the source of the movement.
    case configuredSpeed
    /// Nothing asked for horizontal motion this step.
    case idle
}

/// What the planner asks of one fixed step.
nonisolated struct LocomotionStepPlan: Equatable, Sendable {
    /// World-space horizontal displacement wanted this step, world units. The
    /// only horizontal quantity in the system; the controller turns it into a
    /// collide-and-slide move and never scales it by time again.
    var horizontalDisplacement = SIMD2<Float>()
    /// Upward velocity injected once, this step only, or nil for no takeoff.
    var jumpImpulse: Float?
    /// Water surface height at the capsule, when the step happens submerged
    /// deeply enough to swim. Nil on land.
    var swimSurfaceHeight: Float?
    /// Vertical speed the swimmer is asking for, units per second, positive up.
    /// Ignored out of water.
    var swimVerticalVelocity: Float = 0
    /// Where `horizontalDisplacement` came from, for readouts and tests.
    var motionSource: LocomotionMotionSource = .idle

    var isSwimming: Bool {
        swimSurfaceHeight != nil
    }

    /// A step that asks for nothing. What a paused frame plans, and what a
    /// controller with no planner behaves as.
    static let still = LocomotionStepPlan()
}
