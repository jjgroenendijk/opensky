// The arcane enchanter's game settings. UESP "Skyrim:Leveling" gives the disenchanting
// experience as 1 per 400 gold, which is `fDisenchantSkillUse`. See docs/engine/enchanting.md.

import OpenSkyGameData

nonisolated public struct EnchantingSettings: Equatable, Sendable {
    /// `fDisenchantSkillUse`: base experience per gold of enchantment value.
    public var disenchantSkillUse: Float = 0.0025

    public static let vanilla = Self()

    public init() {}

    /// Base experience for disenchanting an item whose enchantment adds `worth` gold.
    public func disenchantExperience(worth: Int32) -> Float {
        Float(max(0, worth)) * disenchantSkillUse
    }

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fDisenchantSkillUse", into: &settings, \.disenchantSkillUse)
        return settings
    }
}
