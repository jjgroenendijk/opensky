// The arcane enchanter's game settings. UESP "Skyrim:Leveling" gives the disenchanting
// experience as 1 per 400 gold, which is `fDisenchantSkillUse`. See docs/engine/enchanting.md.

public import OpenSkyGameData

nonisolated public struct EnchantingSettings: Equatable, Sendable {
    /// `fDisenchantSkillUse`: base experience per gold of enchantment value.
    public var disenchantSkillUse: Float = 0.0025
    /// `fEnchantingSkillFactor`: scales how much the skill raises a new enchantment's power.
    public var skillFactor: Float = 1.25
    /// `fSkillUsageRechargeMult`: experience per point of charge a soul gem gives a weapon.
    public var rechargeSkillUse: Float = 0.0002

    public static let vanilla = Self()

    public init() {}

    /// Base experience for disenchanting an item whose enchantment adds `worth` gold.
    public func disenchantExperience(worth: Int32) -> Float {
        Float(max(0, worth)) * disenchantSkillUse
    }

    /// Experience for recharging from a soul of `charge` points: a grand soul's 3000 gives 0.6.
    public func rechargeExperience(charge: Float) -> Float {
        max(0, charge) * rechargeSkillUse
    }

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fDisenchantSkillUse", into: &settings, \.disenchantSkillUse)
        store.read("fEnchantingSkillFactor", into: &settings, \.skillFactor)
        store.read("fSkillUsageRechargeMult", into: &settings, \.rechargeSkillUse)
        return settings
    }
}
