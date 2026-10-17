// The settings a weapon hit is scaled by after the block: the player's weapon
// skill, a sneak attack, and the target's worn armour. See
// docs/engine/melee-damage.md, "Skill, sneak attacks and armour".

import Foundation
import OpenSkyGameData

nonisolated public struct WeaponDamageSettings: Equatable, Sendable {
    /// `fDamagePCSkillMax`: the player's damage factor at skill 100.
    public var playerSkillMax: Float = 1.5
    /// `fCombatSneak*Mult`, by weapon family.
    public var sneakOneHandedSword: Float = 3
    public var sneakOneHandedAxe: Float = 3
    public var sneakOneHandedMace: Float = 3
    public var sneakDagger: Float = 3
    public var sneakTwoHandedSword: Float = 2
    public var sneakTwoHandedAxe: Float = 2
    /// `fCombatSneakHandMult`: an unarmed sneak attack.
    public var sneakHand: Float = 2
    /// `fDamageSneakAttackMult`: multiplies every sneak attack.
    public var sneakAttackMult: Float = 1
    /// `fCombatSneakAttackBonusMult`, in percent. No source states its use; a combat
    /// mod lowers it on hard settings, so it is read as a percent scale.
    public var sneakAttackBonusPercent: Float = 100
    /// `fArmorScalingFactor`: percent of damage each point of armour rating stops.
    public var armorScalingFactor: Float = 0.12
    /// `fArmorBaseFactor`: fraction each worn light or heavy piece stops.
    public var armorBaseFactor: Float = 0.03
    /// `fArmorRatingBase`, `fArmorRatingMax`, `fArmorRatingPCMax`: the factor on
    /// a piece's rating at armour skill 0 and at 100.
    public var armorRatingBase: Float = 1
    public var armorRatingMax: Float = 2.5
    public var armorRatingPlayerMax: Float = 1.4
    /// `fMaxArmorRating`: the cap on the stopped damage, in percent.
    public var maxArmorRating: Float = 80
    /// `fClothingArmorScale`: the factor on a clothing piece's rating.
    public var clothingArmorScale: Float = 1
    /// `fSneakAttackSkillUsageMelee`: Sneak experience per melee sneak attack.
    public var sneakSkillUseMelee: Float = 30
    /// `sSuccessfulSneakAttackMain` and `sSuccessfulSneakAttackEnd`, around the multiplier.
    public var sneakNoticeMain = "sSuccessfulSneakAttackMain"
    public var sneakNoticeEnd = "sSuccessfulSneakAttackEnd"

    /// UESP "Skyrim:Sneak": "Melee sneak attacks give 12x as much as ranged sneak
    /// attacks." No setting holds the ranged amount.
    public var sneakSkillUseRanged: Float {
        sneakSkillUseMelee / 12
    }

    public static let vanilla = Self()

    public init() {}

    /// The HUD notice, such as "Sneak attack for 3.0X damage!".
    public func sneakNotice(multiplier: Float) -> String {
        sneakNoticeMain + String(format: "%.1f", multiplier) + sneakNoticeEnd
    }

    /// `text` resolves a string setting through the plugin's string table.
    public static func resolve(
        store: GameSettingStore, text: GameTextResolver = { _ in nil }
    ) -> Self {
        var settings = vanilla
        store.read("fDamagePCSkillMax", into: &settings, \.playerSkillMax)
        store.read("fCombatSneak1HSwordMult", into: &settings, \.sneakOneHandedSword)
        store.read("fCombatSneak1HAxeMult", into: &settings, \.sneakOneHandedAxe)
        store.read("fCombatSneak1HMaceMult", into: &settings, \.sneakOneHandedMace)
        store.read("fCombatSneak1HDaggerMult", into: &settings, \.sneakDagger)
        store.read("fCombatSneak2HSwordMult", into: &settings, \.sneakTwoHandedSword)
        store.read("fCombatSneak2HAxeMult", into: &settings, \.sneakTwoHandedAxe)
        store.read("fCombatSneakHandMult", into: &settings, \.sneakHand)
        store.read("fDamageSneakAttackMult", into: &settings, \.sneakAttackMult)
        store.read("fCombatSneakAttackBonusMult", into: &settings, \.sneakAttackBonusPercent)
        store.read("fArmorScalingFactor", into: &settings, \.armorScalingFactor)
        store.read("fArmorBaseFactor", into: &settings, \.armorBaseFactor)
        store.read("fArmorRatingBase", into: &settings, \.armorRatingBase)
        store.read("fArmorRatingMax", into: &settings, \.armorRatingMax)
        store.read("fArmorRatingPCMax", into: &settings, \.armorRatingPlayerMax)
        store.read("fMaxArmorRating", into: &settings, \.maxArmorRating)
        store.read("fClothingArmorScale", into: &settings, \.clothingArmorScale)
        store.read("fSneakAttackSkillUsageMelee", into: &settings, \.sneakSkillUseMelee)
        if let main = store.text("sSuccessfulSneakAttackMain").flatMap({ text($0) }) {
            settings.sneakNoticeMain = main
        }
        if let end = store.text("sSuccessfulSneakAttackEnd").flatMap({ text($0) }) {
            settings.sneakNoticeEnd = end
        }
        return settings
    }
}
