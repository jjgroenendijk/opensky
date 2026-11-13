// What one magic item's application did to one target, which the player's
// "resisted" notices read. See docs/engine/magic.md#hit-notices.

extension ActiveEffectRuntime {
    /// Entries that acted, entries the target refused, and whether a refusal was a level cap.
    nonisolated public struct ApplicationTally: Equatable, Sendable {
        public var landed = 0
        public var refused = 0
        public var aboveLevelCap = false

        public init() {}

        mutating func note(_ reason: MagicEffectPlanFailure) {
            refused += 1
            if case .aboveLevelCap = reason {
                aboveLevelCap = true
            }
        }
    }
}
