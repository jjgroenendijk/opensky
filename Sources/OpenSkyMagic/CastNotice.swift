// The HUD notices of a refused cast or shout, from the `sMagicCast*` string settings
// and `sFailSpendSoul`. See docs/engine/spellcasting.md.

import OpenSkyGameData

nonisolated public enum CastNoticeText: String, GameSettingTextKey {
    case insufficientMagicka = "sMagicCastInsufficientMagicka"
    case powerUsed = "sMagicCastPowerUsed"
    case shoutWhileCasting = "sMagicCastShoutWhileCasting"
    case castWhileShouting = "sMagicCastCastWhileShouting"
    case playerDisarmed = "sPlayerDisarmedMessage"
    case enhanceWeaponNoWeapon = "sMagicEnhanceWeaponNoWeapon"
    case enhanceWeaponEnchanted = "sMagicEnhanceWeaponWeaponEnchanted"
    case guideNoMarker = "sMagicGuideNoMarker"
    case guideNoPath = "sMagicGuideNoPath"
    case flyingMountNoCast = "sTESVDLC2FlyingDragonNoCastMessage"
    case telekinesisNoRecast = "sMagicTelekinesisNoRecast"

    public var fallback: String {
        switch self {
        case .insufficientMagicka: "Not enough magicka."
        case .powerUsed: "This power is spent for today."
        case .shoutWhileCasting: "You cannot shout during a cast."
        case .castWhileShouting: "You cannot cast during a shout."
        case .playerDisarmed: "You have been disarmed!"
        case .enhanceWeaponNoWeapon: "You need a melee weapon equipped."
        case .enhanceWeaponEnchanted: "This weapon is already enchanted."
        case .guideNoMarker: "There is no quest target to guide you to."
        case .guideNoPath: "No path leads to the quest target."
        case .flyingMountNoCast: "You cannot cast that type of spell while riding a dragon."
        case .telekinesisNoRecast: "You're already holding something."
        }
    }

    /// The notice the player sees for `failure`, or nil when the game shows none.
    public static func notice(for failure: SpellCastFailure) -> Self? {
        switch failure {
        case .insufficientMagicka: .insufficientMagicka
        case .powerAlreadyUsedToday: .powerUsed
        case .notFromFlyingMount: .flyingMountNoCast
        case .noSpellReadied, .unknownSpell, .notCharged, .deliveryUnsupported,
             .abilityNotCastable, .notDualCastable: nil
        }
    }
}
