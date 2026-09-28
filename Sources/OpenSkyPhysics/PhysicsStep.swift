// The fixed-step clock and the world constants every physics integrator shares.

nonisolated public enum PhysicsStep {
    /// Downward acceleration in game units per second squared.
    public static let gravity: Float = 1400
    /// The steepest surface a capsule still stands on.
    public static let maximumSlopeDegrees: Float = 50
    /// One integration step.
    public static let fixedTimeStep: Float = 1 / 120
    /// The longest frame the accumulator takes in, so a stall does not queue
    /// a burst of steps.
    public static let maximumFrameTime: Float = 0.1
}
