// An actor's resistance as a fraction. The player's cap is 85%. Resist Magic
// applies first, then the fire, frost, or shock resistance. The cap is a constant
// because no game setting holds it. Sources are in docs/engine/actor-values.md.

import Foundation

/// The caps a resistance query applies.
nonisolated public struct ActorResistanceSettings: Equatable, Sendable {
    /// Largest fraction of damage the *player* may resist through a capped
    /// resistance. 0.85 per the two UESP pages quoted above.
    public var playerCapFraction: Float
    /// Largest fraction anyone may resist through an uncapped resistance —
    /// total immunity, which is what a 100% NPC resistance grants.
    public var immunityFraction: Float

    public static let documentedDefaults = ActorResistanceSettings(
        playerCapFraction: 0.85,
        immunityFraction: 1
    )
}

nonisolated public enum ActorResistance: Sendable {
    /// The resistance actor values that hold a percentage, and are therefore
    /// readable as a fraction by the query below.
    public static let percentageIndices: Set<Int32> = [
        ActorValueIndex.poisonResist,
        ActorValueIndex.resistFire,
        ActorValueIndex.resistShock,
        ActorValueIndex.resistFrost,
        ActorValueIndex.resistMagic,
        ActorValueIndex.resistDisease
    ]

    /// Whether `index` names a percentage resistance.
    public static func isPercentage(index: Int32) -> Bool {
        percentageIndices.contains(index)
    }

    /// Whether the 85% cap applies to `index`, which every percentage
    /// resistance but disease answers yes to.
    public static func isCapped(index: Int32) -> Bool {
        isPercentage(index: index) && index != ActorValueIndex.resistDisease
    }

    /// The damage fraction `percentagePoints` removes, capped for `index`. Negative
    /// points are a weakness and stay negative: -30 takes 130% damage
    /// (<https://en.uesp.net/wiki/Skyrim:Weakness_to_Fire>). The 85% cap is player-only.
    public static func fraction(
        percentagePoints: Float,
        at index: Int32,
        isPlayer: Bool,
        settings: ActorResistanceSettings = .documentedDefaults
    ) -> Float {
        guard percentagePoints.isFinite else { return 0 }
        let cap = isPlayer && isCapped(index: index)
            ? settings.playerCapFraction
            : settings.immunityFraction
        return min(percentagePoints / 100, max(0, cap))
    }
}
