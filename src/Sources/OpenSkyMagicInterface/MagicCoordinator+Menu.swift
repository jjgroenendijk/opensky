import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// One known spell as the magic menu lists it.
nonisolated public struct MagicMenuSpell: Equatable, Sendable {
    public let name: String
    public let isReadied: Bool
    /// The tab's title: a school, "SHOUTS", or "POWERS", or nil for no tab of its own.
    public let category: String?
    public let card: MagicMenuSpellCard?

    public init(
        name: String,
        isReadied: Bool,
        category: String? = nil,
        card: MagicMenuSpellCard? = nil
    ) {
        self.name = name
        self.isReadied = isReadied
        self.category = category
        self.card = card
    }
}

/// What the magic menu's item card shows for one spell.
nonisolated public struct MagicMenuSpellCard: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case spell
        /// A power or lesser power: no cost and no level.
        case power
        /// A shout: its words, and `cost` holds the recharge in seconds.
        case shout(words: [MagicMenuShoutWord])
        /// An effect on the player, with the whole seconds it has left; nil for one with
        /// no end.
        case activeEffect(secondsLeft: Int?)
    }

    public let kind: Kind
    /// The effect lines, joined.
    public let effects: String
    /// Magicka per cast, or per second for a concentration spell.
    public let cost: Int
    public let costIsPerSecond: Bool
    /// "Novice" to "Master".
    public let level: String

    public init(kind: Kind, effects: String, cost: Int, costIsPerSecond: Bool, level: String) {
        self.kind = kind
        self.effects = effects
        self.cost = cost
        self.costIsPerSecond = costIsPerSecond
        self.level = level
    }
}

/// One word of a shout as its card shows it.
nonisolated public struct MagicMenuShoutWord: Equatable, Sendable {
    /// The word in dragon letters, such as "Fus".
    public let dragon: String
    /// The word in the player's language, such as "Force".
    public let translation: String
    public let isUnlocked: Bool

    public init(dragon: String, translation: String, isUnlocked: Bool) {
        self.dragon = dragon
        self.translation = translation
        self.isUnlocked = isUnlocked
    }
}

extension MagicMenuSpellCard {
    /// A card with only a kind and a text, for a shout or an effect.
    public init(kind: Kind, effects: String, cost: Int = 0) {
        self.init(kind: kind, effects: effects, cost: cost, costIsPerSecond: false, level: "")
    }
}
