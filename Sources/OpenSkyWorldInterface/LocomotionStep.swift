public import OpenSkyPhysics
import simd

/// What the planner asks of one fixed step.
nonisolated public struct LocomotionStepPlan: Equatable, Sendable {
    public init() {}

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
    /// The water over the feet, or nil on dry land.
    public var water: WaterReading?
    /// What a current added to this step, game units per second; already in
    /// `horizontalDisplacement`.
    public var waterPush = SIMD3<Float>()

    public var isSwimming: Bool {
        swimSurfaceHeight != nil
    }

    /// A step that asks for nothing. What a paused frame plans, and what a
    /// controller with no planner behaves as.
    public static let still = LocomotionStepPlan()
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
