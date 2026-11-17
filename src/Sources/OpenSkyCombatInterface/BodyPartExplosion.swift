// What a killing hit does to an explodable body part: blow it off, cut it off, or
// leave it. See docs/engine/explosion-effects.md#exploding-body-parts.

/// An explodable part of a dying actor, from its race's `BPTD`.
nonisolated public struct ExplodablePart: Equatable, Sendable {
    public let node: String
    /// The part's explode chance, in percent.
    public let chance: Int
    /// True when the chance is used as it is, not scaled by the game's percentage.
    public let isChanceAbsolute: Bool

    public init(node: String, chance: Int, isChanceAbsolute: Bool) {
        self.node = node
        self.chance = chance
        self.isChanceAbsolute = isChanceAbsolute
    }
}

nonisolated public enum BodyPartCut: Equatable, Sendable {
    case explode, sever, none

    /// The cut for one roll `roll` from 0 to 99. `explodePercent` and `dismemberChance`
    /// are the game's settings, 75 and 50 by default.
    public static func of(
        _ part: ExplodablePart,
        roll: Int,
        explodePercent: Int,
        dismemberChance: Int
    ) -> Self {
        let explodes = part.isChanceAbsolute
            ? part.chance >= 100 || roll < part.chance
            : roll * 100 < explodePercent * part.chance
        if explodes {
            return .explode
        }
        return roll < dismemberChance ? .sever : .none
    }
}
