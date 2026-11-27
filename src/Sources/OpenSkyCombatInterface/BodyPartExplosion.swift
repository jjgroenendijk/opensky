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
            : roll < explodePercent * part.chance / 100
        if explodes {
            return .explode
        }
        return roll < dismemberChance ? .sever : .none
    }

    /// The cut after the weapon's `DNAM` On Hit setting: 1 turns a success into a
    /// sever, 2 into an explode, and 3 stops both.
    public func applying(weaponOnHit setting: UInt32) -> Self {
        guard self != .none else { return self }
        switch setting {
        case 1: return .sever
        case 2: return .explode
        case 3: return .none
        default: return self
        }
    }
}
