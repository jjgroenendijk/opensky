import Foundation

nonisolated public enum MagicEffectActionOutcome: Equatable, Sendable {
    case idle
    case unavailable
    case nothingToConsume
    case consumed(item: String, MagicItemConsumeOutcome?)
    /// `reason` is the thrown error's description.
    case consumeFailed(item: String, reason: String)
    case dispelled(removed: Int)
    case boundWeaponFailed(reason: String)
    case boundWeaponStayed(reason: String)
    case raceChangeFailed(actor: String)
}

nonisolated public enum CastingActionOutcome: Equatable, Sendable {
    case idle
    case unavailable
    case learnedStartSpells(granted: Int, held: Int)
    case noTome
    case unresolvedTome(book: String, plugin: String)
    case readTome(SpellTomeReading, book: String)
    case noSpellsKnown
    case selected(spell: String)
    case noSpellSelected
    case readied(SpellEquipChange, spell: String, unequipped: [String])
    case readyFailed(spell: String, reason: String)
    case cast(SpellCastOutcome)
    case noUnreadSkillBook
    case unresolvedBook(String)
    case bookAlreadyRead(String)
    case readSkillBook(String, levelsRaised: Int)

    package var skillBookText: String {
        switch self {
        case .noUnreadSkillBook: "The player carries no unread skill book."
        case let .unresolvedBook(name): "Could not resolve \(name)."
        case let .bookAlreadyRead(name): "\(name) was already read."
        case let .readSkillBook(name, raised): "Read \(name): the skill rose \(raised) level(s)."
        default: ""
        }
    }
}
