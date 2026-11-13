// The magic menu's shout texts: spending a dragon soul on a word, and the refusals.
// See docs/engine/shouts.md#magic-menu.

public import OpenSkyGameData

nonisolated public enum ShoutMenuText: String, GameSettingTextKey {
    case confirmSpendSoul = "sConfirmSpendSoul"
    case failSpendSoul = "sFailSpendSoul"
    case failShouting = "sFailShouting"

    public var fallback: String {
        switch self {
        case .confirmSpendSoul: "Spend Soul?"
        case .failSpendSoul: "Dragon Souls are required to unlock shouts."
        case .failShouting: "You cannot change shouts while shouting."
        }
    }
}

/// What the unlock key does on a shout: ask before a soul is spent, or refuse.
nonisolated public enum ShoutUnlockStep: Equatable, Sendable {
    case ask(String)
    case refuse(String)
}
