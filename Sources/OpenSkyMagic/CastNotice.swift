// The HUD notices of a refused cast or shout, from the `sMagicCast*` string settings
// and `sFailSpendSoul`. See docs/engine/spellcasting.md.

import OpenSkyGameData

nonisolated public enum CastNoticeText: String, GameSettingTextKey {
    case insufficientMagicka = "sMagicCastInsufficientMagicka"
    case powerUsed = "sMagicCastPowerUsed"
    case shoutWhileCasting = "sMagicCastShoutWhileCasting"
    case castWhileShouting = "sMagicCastCastWhileShouting"
    case playerDisarmed = "sPlayerDisarmedMessage"

    public var fallback: String {
        switch self {
        case .insufficientMagicka: "Not enough magicka."
        case .powerUsed: "This power is spent for today."
        case .shoutWhileCasting: "You cannot shout during a cast."
        case .castWhileShouting: "You cannot cast during a shout."
        case .playerDisarmed: "You have been disarmed!"
        }
    }

    /// The notice the player sees for `failure`, or nil when the game shows none.
    public static func notice(for failure: SpellCastFailure) -> Self? {
        switch failure {
        case .insufficientMagicka: .insufficientMagicka
        case .powerAlreadyUsedToday: .powerUsed
        case .noSpellReadied, .unknownSpell, .notCharged, .deliveryUnsupported,
             .abilityNotCastable, .notDualCastable: nil
        }
    }
}
