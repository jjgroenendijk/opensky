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
