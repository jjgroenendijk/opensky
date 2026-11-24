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
        /// Health an arrow took off. A spell's damage goes through its effects instead.
        public var damage: Float = 0
        /// For a spell: the actors it was applied to, the effect entries it handed on,
        /// and the targets that refused it. Nil for an arrow or a spell that reached
        /// nobody.
        public var spellTargets: Int?
        public var spellEntries: Int?
        public var spellRefusals: Int?
        /// Each hostile entry's magnitude after resistance, in application order.
        public var spellMagnitudes: [Float] = []
        /// For a spell: entries that landed, entries skipped for their conditions or an
        /// unresolved effect, and the health the hit took off.
        public var spellLanded: Int?
        public var spellSkipped: Int?
        public var spellHealthTaken: Float?
        public var spellOutcomes: [String] = []

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
