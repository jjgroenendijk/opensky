// The notices of a poison the player cannot put on a weapon. The texts are string
// settings. See docs/engine/alchemy.md#poison-on-a-weapon.

public import OpenSkyGameData

nonisolated public enum PoisonText: String, GameSettingTextKey {
    case noWeapon = "sPoisonNoWeaponMessage"
    case alreadyPoisoned = "sPoisonAlreadyPoisonedMessage"
    case cannotPoison = "sPoisonUnableToPoison"
    /// The question before a poison goes on a melee weapon; the weapon's name follows.
    case confirm = "sPoisonConfirmMessage"
    /// The question for a bow or crossbow; the poison's name follows.
    case confirmBow = "sPoisonBowConfirmMessage"

    public var fallback: String {
        switch self {
        case .noWeapon: "You must first equip a weapon to poison it."
        case .alreadyPoisoned: "The current weapon is already poisoned."
        case .cannotPoison: "Current weapon cannot be poisoned."
        case .confirm: "Do you want to poison the "
        case .confirmBow: "Do you want to poison your next shot with the "
        }
    }
}

nonisolated public enum PoisonQuestion {
    /// The game's text ends in "the ", so the name and a question mark follow it.
    public static func text(
        isRanged: Bool, weapon: String, poison: String, texts: GameSettingTexts<PoisonText>
    ) -> String {
        isRanged ? "\(texts[.confirmBow])\(poison)?" : "\(texts[.confirm])\(weapon)?"
    }
}
