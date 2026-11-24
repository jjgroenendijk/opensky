// The arcane enchanter's numbers, from UESP "Skyrim:Enchanting_Effects": how strong a new
// enchantment is, the magnitude slider, a weapon's charge, and what one use costs. Values
// in, values out. See docs/engine/enchanting.md.

import Foundation
public import OpenSkyFormatsESM
import OpenSkyMagicInterface

/// One base enchantment as the rules see it.
nonisolated struct EnchantingBase: Equatable, Sendable {
    /// The base record's cost per use, after `Mod Spell Cost`.
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
    /// The soul's charge after `Mod Soul Gem Enchanting`; nil is the soul's own.
    var charge: Float?
    /// The first base's first magnitude, or its duration where power changes only that.
    /// The slider runs up to this value times the power.
    var baseMagnitude: Float = 0
    /// The magnitude the slider chose; nil is the highest.
    var chosen: Int?
}

/// How a new enchantment changes its base records.
nonisolated struct EnchantingScale: Equatable, Sendable {
    /// Per base, a factor on every magnitude or duration the effect lets power change.
    let powers: [Float]
    /// A weapon's full charge, fraction dropped; zero on apparel.
    let capacity: Float
    /// What one use costs, with the skill at the moment of making, fraction dropped.
    let costPerUse: Float
    /// The uses the menu shows: the charge over the cost before its fraction is dropped.
    var uses = 0
}

/// A weapon enchantment's magnitude slider.
nonisolated struct EnchantingSlider: Equatable, Sendable {
    let maximum: Int
    let step: Int
    /// The chosen value, kept within 1 and the maximum.
    let value: Int
    /// The uses the menu shows at this value.
    var uses = 0
}

nonisolated enum EnchantingRules {
    /// The skill term must stay below 200, where a use would cost nothing.
    static let skillCap = MadeEnchantment.skillCap
    /// A grand soul's charge, which the soul's share is measured against.
    static let grandCharge: Float = 3000

    /// `1 + (factor - 1) * (skill/100) * max(0.01, (skill - 14) / 85)`: 1.253 at skill 100
    /// with the vanilla factor 1.25.
    static func skillMultiplier(
        _ skill: Float, factor: Float = EnchantingSettings.vanilla.skillFactor
    ) -> Float {
        let level = min(max(0, skill), skillCap)
        return 1 + (factor - 1) * (level / 100) * max(0.01, (level - 14) / 85)
    }

    /// The soul's value over a grand soul's: 1 grand, 2/3 greater, down to 1/12 petty.
    static func soulMultiplier(_ soul: SoulLevel) -> Float {
        SoulTrap.charge(of: soul) / grandCharge
    }

    /// The highest magnitude: the first base's magnitude times its power, rounded down.
    static func maximumMagnitude(_ input: EnchantingInput) -> Int {
        guard let first = input.bases.first else { return 0 }
        let highest = (input.baseMagnitude * strength(first, input)).rounded(.down)
        return highest.isFinite ? Int(max(0, min(highest, Float(Int32.max)))) : 0
    }

    /// The step grows with the maximum: 1 up to 30, then 2, 5 above 60, 10 above 120.
    static func sliderStep(maximum: Int) -> Int {
        switch maximum {
        case ...30: 1
        case ...60: 2
        case ...120: 5
        default: 10
        }
    }

    /// A weapon's slider, or nil when its highest magnitude is 1 or less.
    static func slider(_ input: EnchantingInput) -> EnchantingSlider? {
        let maximum = maximumMagnitude(input)
        guard maximum > 1 else { return nil }
        return EnchantingSlider(
            maximum: maximum, step: sliderStep(maximum: maximum),
            value: min(max(1, input.chosen ?? maximum), maximum)
        )
    }

    /// Apparel: the magnitude is the maximum times the soul's share, at least 1. Nothing
    /// is spent, so the cost only adds to the item's value.
    static func apparel(_ input: EnchantingInput) -> EnchantingScale {
        let maximum = maximumMagnitude(input)
        var share = soulMultiplier(input.soul)
        if maximum > 0 {
            share = max(1, (Float(maximum) * share).rounded(.down)) / Float(maximum)
        }
        return EnchantingScale(
            powers: input.bases.map { share * strength($0, input) },
            capacity: 0,
            costPerUse: useCost(input.bases, share: share, skill: input.skill).rounded(.down)
        )
    }

    /// A weapon: the soul sets the charge, not the power. The slider's share of the
    /// maximum scales every power and the cost.
    static func weapon(_ input: EnchantingInput) -> EnchantingScale {
        let charge = input.charge ?? SoulTrap.charge(of: input.soul)
        let share = slider(input).map { Float($0.value) / Float($0.maximum) } ?? 1
        let capacity = max(0, charge.rounded(.down))
        let cost = useCost(input.bases, share: share, skill: input.skill)
        var scale = EnchantingScale(
            powers: input.bases.map { share * strength($0, input) },
            capacity: capacity,
            costPerUse: cost.rounded(.down)
        )
        scale.uses = cost > 0 ? Int(min((max(0, charge) / cost).rounded(.down), 1e9)) : 0
        return scale
    }

    /// `3 * (sum of costs * share)^1.1 * (1 - sqrt(skill/200))`.
    static func useCost(_ bases: [EnchantingBase], share: Float, skill: Float) -> Float {
        let cost = bases.reduce(0) { $0 + max(0, $1.cost) } * share
        let use = 3 * pow(cost, 1.1) * MadeEnchantment.skillCostFactor(skill)
        return use.isFinite ? max(0, use) : 0
    }

    private static func strength(_ base: EnchantingBase, _ input: EnchantingInput) -> Float {
        skillMultiplier(input.skill, factor: input.skillFactor) * max(0, base.perkFactor)
    }

    /// UESP "Skyrim:Leveling": 1 per item enchanted.
    static let enchantExperience: Float = 1
}
