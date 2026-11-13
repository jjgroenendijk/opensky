// The arcane enchanter's numbers, from UESP "Skyrim:Enchanting_Effects": how strong a new
// enchantment is, how much charge a weapon gets, and what one use costs. Values in,
// values out. See docs/engine/enchanting.md.

import Foundation
public import OpenSkyFormatsESM
import OpenSkyMagicInterface

/// One base enchantment as the rules see it.
nonisolated struct EnchantingBase: Equatable, Sendable {
    /// The base record's cost per use, as the record computes it.
    var cost: Float
    /// Entry point 77 for this base: the Enchanter perks and their kin, as a factor.
    var perkFactor: Float

    init(cost: Float, perkFactor: Float = 1) {
        self.cost = cost
        self.perkFactor = perkFactor
    }
}

/// What one new enchantment is made from.
nonisolated struct EnchantingInput: Equatable, Sendable {
    /// The Enchanting skill as it is now. Without the Unofficial Patch, a Fortify
    /// Enchanting potion raises this value itself, so the potion is inside it.
    var skill: Float
    var soul: SoulLevel
    var bases: [EnchantingBase]
    /// `fEnchantingSkillFactor`: the power gain at skill 100 is about this minus 1.
    var skillFactor: Float = EnchantingSettings.vanilla.skillFactor
}

/// How a new enchantment changes its base records.
nonisolated struct EnchantingScale: Equatable, Sendable {
    /// Per base, a factor on every magnitude or duration the effect lets power change.
    let powers: [Float]
    /// A weapon's full charge; zero on apparel.
    let capacity: Float
    /// What one hit spends at the skill it was made with; zero on apparel.
    let costPerUse: Float
    /// `costPerUse` without the skill term, which each use applies again.
    let unskilledCostPerUse: Float

    init(
        powers: [Float], capacity: Float, costPerUse: Float, unskilledCostPerUse: Float = 0
    ) {
        self.powers = powers
        self.capacity = capacity
        self.costPerUse = costPerUse
        self.unskilledCostPerUse = unskilledCostPerUse
    }
}

nonisolated enum EnchantingRules {
    /// The skill term must stay below 200, where a use would cost nothing.
    static let skillCap = MadeEnchantment.skillCap

    /// `1 + (factor - 1) * (skill/100) * max(0.01, (skill - 14) / 85)`: 1.253 at skill 100
    /// with the vanilla factor 1.25.
    static func skillMultiplier(
        _ skill: Float, factor: Float = EnchantingSettings.vanilla.skillFactor
    ) -> Float {
        let level = min(max(0, skill), skillCap)
        return 1 + (factor - 1) * (level / 100) * max(0.01, (level - 14) / 85)
    }

    /// A grand soul gives the base magnitude; each smaller soul gives a fixed share.
    static func soulMultiplier(_ soul: SoulLevel) -> Float {
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
    static func apparel(_ input: EnchantingInput) -> EnchantingScale {
        let soul = soulMultiplier(input.soul)
        return EnchantingScale(
            powers: input.bases.map { soul * strength($0, input) },
            capacity: 0,
            costPerUse: 0
        )
    }

    /// A weapon: the soul sets the charge, not the power. The costs of two bases add up.
    /// A soul too small for one whole use lowers every power until it buys one.
    static func weapon(_ input: EnchantingInput) -> EnchantingScale {
        let capacity = SoulTrap.charge(of: input.soul)
        let skillFactor = MadeEnchantment.skillCostFactor(input.skill)
        let fullCost = input.bases.reduce(0) { $0 + useCost($1.cost, skillFactor: skillFactor) }
        let powers = input.bases.map { strength($0, input) }
        guard fullCost > capacity, capacity > 0 else {
            return EnchantingScale(
                powers: powers, capacity: capacity, costPerUse: fullCost,
                unskilledCostPerUse: fullCost / skillFactor
            )
        }
        // A use costs `share^1.1` of the full cost, so this share costs the whole soul.
        let share = pow(capacity / fullCost, 1 / 1.1)
        return EnchantingScale(
            powers: powers.map { $0 * share }, capacity: capacity, costPerUse: capacity,
            unskilledCostPerUse: capacity / skillFactor
        )
    }

    /// `3 * cost^1.1 * (1 - sqrt(skill/200))`.
    static func useCost(_ cost: Float, skillFactor: Float) -> Float {
        3 * pow(max(0, cost), 1.1) * skillFactor
    }

    private static func strength(_ base: EnchantingBase, _ input: EnchantingInput) -> Float {
        skillMultiplier(input.skill, factor: input.skillFactor) * max(0, base.perkFactor)
    }

    /// UESP "Skyrim:Leveling": 1 per item enchanted.
    static let enchantExperience: Float = 1
}
