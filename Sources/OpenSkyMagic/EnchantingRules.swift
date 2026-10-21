// The arcane enchanter's numbers, from UESP "Skyrim:Enchanting_Effects": how strong a new
// enchantment is, how much charge a weapon gets, and what one use costs. Values in,
// values out. See docs/engine/enchanting.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// One base enchantment as the rules see it.
nonisolated public struct EnchantingBase: Equatable, Sendable {
    /// The base record's cost per use, as the record computes it.
    public var cost: Float
    /// Entry point 77 for this base: the Enchanter perks and their kin, as a factor.
    public var perkFactor: Float

    public init(cost: Float, perkFactor: Float = 1) {
        self.cost = cost
        self.perkFactor = perkFactor
    }
}

/// What one new enchantment is made from.
nonisolated public struct EnchantingInput: Equatable, Sendable {
    /// The Enchanting skill as it is now. Without the Unofficial Patch, a Fortify
    /// Enchanting potion raises this value itself, so the potion is inside it.
    public var skill: Float
    public var soul: SoulLevel
    public var bases: [EnchantingBase]

    public init(skill: Float, soul: SoulLevel, bases: [EnchantingBase]) {
        self.skill = skill
        self.soul = soul
        self.bases = bases
    }
}

/// How a new enchantment changes its base records.
nonisolated public struct EnchantingScale: Equatable, Sendable {
    /// Per base, a factor on every magnitude or duration the effect lets power change.
    public let powers: [Float]
    /// A weapon's full charge; zero on apparel.
    public let capacity: Float
    /// What one hit spends; zero on apparel.
    public let costPerUse: Float

    public init(powers: [Float], capacity: Float, costPerUse: Float) {
        self.powers = powers
        self.capacity = capacity
        self.costPerUse = costPerUse
    }
}

nonisolated public enum EnchantingRules {
    /// The skill term must stay below 200, where a use would cost nothing.
    public static let skillCap: Float = 199

    /// `1 + (skill/100) * (skill/100 - 0.14) / 3.4`: about 1.25 at skill 100.
    public static func skillMultiplier(_ skill: Float) -> Float {
        let level = min(max(0, skill), skillCap) / 100
        return 1 + level * (level - 0.14) / 3.4
    }

    /// A grand soul gives the base magnitude; each smaller soul gives a fixed share.
    public static func soulMultiplier(_ soul: SoulLevel) -> Float {
        switch soul {
        case .grand: 1
        case .greater: 2 / 3
        case .common: 1 / 3
        case .lesser: 1 / 6
        case .petty: 1 / 12
        case .empty, .unknown: 0
        }
    }

    /// Apparel: the soul scales the power, and nothing is spent.
    public static func apparel(_ input: EnchantingInput) -> EnchantingScale {
        let soul = soulMultiplier(input.soul)
        return EnchantingScale(
            powers: input.bases.map { soul * strength($0, skill: input.skill) },
            capacity: 0,
            costPerUse: 0
        )
    }

    /// A weapon: the soul sets the charge, not the power. The costs of two bases add up.
    /// A soul too small for one whole use lowers every power until it buys one.
    public static func weapon(_ input: EnchantingInput) -> EnchantingScale {
        let capacity = SoulTrap.charge(of: input.soul)
        let skillFactor = 1 - (min(max(0, input.skill), skillCap) / 200).squareRoot()
        let fullCost = input.bases.reduce(0) { $0 + useCost($1.cost, skillFactor: skillFactor) }
        let powers = input.bases.map { strength($0, skill: input.skill) }
        guard fullCost > capacity, capacity > 0 else {
            return EnchantingScale(powers: powers, capacity: capacity, costPerUse: fullCost)
        }
        // A use costs `share^1.1` of the full cost, so this share costs the whole soul.
        let share = pow(capacity / fullCost, 1 / 1.1)
        return EnchantingScale(
            powers: powers.map { $0 * share }, capacity: capacity, costPerUse: capacity
        )
    }

    /// `3 * cost^1.1 * (1 - sqrt(skill/200))`.
    static func useCost(_ cost: Float, skillFactor: Float) -> Float {
        3 * pow(max(0, cost), 1.1) * skillFactor
    }

    private static func strength(_ base: EnchantingBase, skill: Float) -> Float {
        skillMultiplier(skill) * max(0, base.perkFactor)
    }

    /// UESP "Skyrim:Leveling": 1 per item enchanted.
    public static let enchantExperience: Float = 1
    /// UESP "Skyrim:Leveling": 1 per 400 gold of enchantment value disenchanted.
    public static let disenchantGoldPerExperience: Float = 400

    /// UESP "Skyrim:Leveling": what recharging a weapon from a soul of this size gives.
    public static func rechargeExperience(_ soul: SoulLevel) -> Float {
        switch soul {
        case .petty: 0.05
        case .lesser: 0.1
        case .common: 0.2
        case .greater: 0.4
        case .grand: 0.6
        case .empty, .unknown: 0
        }
    }
}
