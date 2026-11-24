// What one magic item's application did to one target, which the player's
// "resisted" notices read. See docs/engine/magic.md#hit-notices.

extension ActiveEffectRuntime {
    /// Entries that acted, entries the target refused, and whether a refusal was a level cap.
    nonisolated public struct ApplicationTally: Equatable, Sendable {
        public var landed = 0
        public var refused = 0
        /// Entries skipped because their conditions failed or their effect did not resolve.
        public var skipped = 0
        /// What became of each entry, in order: `landed`, `unresolved`,
        /// `effectConditions`, `entryConditions`, or the plan or refusal reason.
        public var outcomes: [String] = []
        public var aboveLevelCap = false

        public init() {}

        mutating func note(_ reason: MagicEffectPlanFailure) {
            refused += 1
            outcomes.append("refused: \(reason)")
            if case .aboveLevelCap = reason {
                aboveLevelCap = true
            }
        }
    }
}
