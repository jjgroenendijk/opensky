// What `game state projectiles` shows: the shots in the air, the arrows left standing,
// and how the newest shots ended. See docs/engine/projectiles.md.

public import OpenSkyFormatsESM

nonisolated public struct ProjectileReadout: Equatable, Sendable {
    /// One finished shot.
    nonisolated public struct Landing: Equatable, Sendable {
        public var outcome: String
        public var position: SIMD3<Float>
        public var target: ReferenceKey?
        /// The MATT of the surface struck.
        public var material: FormID?
        public var stuck = false
        public var bounced = false

        public init(outcome: String, position: SIMD3<Float>) {
            self.outcome = outcome
            self.position = position
        }
    }

    public var inFlight = 0
    /// Arrows in the air after a bounce.
    public var bouncing = 0
    /// The spawned arrows standing in the world, oldest first.
    public var stuck: [ReferenceKey] = []
    /// The newest finished shots, oldest first.
    public var landings: [Landing] = []

    public init() {}
}
