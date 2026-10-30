// The notices of a poison the player cannot put on a weapon. The texts are string
// settings. See docs/engine/alchemy.md#poison-on-a-weapon.

import OpenSkyGameData

nonisolated public enum PoisonText: String, GameSettingTextKey {
    case noWeapon = "sPoisonNoWeaponMessage"
    case alreadyPoisoned = "sPoisonAlreadyPoisonedMessage"
    case cannotPoison = "sPoisonUnableToPoison"

    public var fallback: String {
        switch self {
        case .noWeapon: "You must first equip a weapon to poison it."
        case .alreadyPoisoned: "The current weapon is already poisoned."
        case .cannotPoison: "Current weapon cannot be poisoned."
        }
    }
}

nonisolated extension AlchemyActionOutcome {
    /// The outcome's line, with a refusal in the load order's wording.
    public func text(_ texts: GameSettingTexts<PoisonText>) -> String {
        switch self {
        case .noWeapon: texts[.noWeapon]
        case .alreadyPoisoned: texts[.alreadyPoisoned]
        case .cannotPoison: texts[.cannotPoison]
        default: text
        }
    }
}
