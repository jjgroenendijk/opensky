// What the last magic-effect and casting control did, as values. Only the `text`
// formatters build lines; the sentence helpers live in `MagicCore`.

import Foundation
import OpenSkyMagicInterface

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

    public var text: String {
        switch self {
        case .idle: "No magic action yet."
        case .unavailable: MagicCore.effectsUnavailableText
        case .nothingToConsume: "The player carries nothing to eat or drink."
        case let .consumed(item, outcome): MagicCore.consumeText(name: item, outcome: outcome)
        case let .consumeFailed(item, reason): "Could not consume \(item): " + reason
        case let .dispelled(removed): MagicCore.dispelText(removed: removed)
        case let .boundWeaponFailed(reason): "Bound weapon failed: " + reason
        case let .boundWeaponStayed(reason): "Bound weapon stayed: " + reason
        case let .raceChangeFailed(actor): "Race change failed: \(actor) cannot change race"
        }
    }
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

    public var text: String {
        switch self {
        case .idle: "No casting action yet."
        case .unavailable: MagicCore.castingUnavailableText
        case let .learnedStartSpells(granted, held):
            MagicCore.startSpellsText(granted: granted, held: held)
        case .noTome: "The player carries no spell tome."
        case let .unresolvedTome(book, plugin): "Could not resolve \(book) in \(plugin)."
        case let .readTome(reading, book): MagicCore.readingText(reading, book: book)
        case .noSpellsKnown: "The player knows no spells to select."
        case let .selected(spell): "Selected \(spell)."
        case .noSpellSelected: "No spell selected to ready."
        case let .readied(change, spell, unequipped):
            MagicCore.readyText(change, name: spell, itemNames: unequipped)
        case let .readyFailed(spell, reason): "Could not ready \(spell): " + reason
        case let .cast(outcome): MagicCore.castText(outcome)
        case .noUnreadSkillBook, .unresolvedBook, .bookAlreadyRead, .readSkillBook:
            skillBookText
        }
    }

    private var skillBookText: String {
        switch self {
        case .noUnreadSkillBook: "The player carries no unread skill book."
        case let .unresolvedBook(name): "Could not resolve \(name)."
        case let .bookAlreadyRead(name): "\(name) was already read."
        case let .readSkillBook(name, raised): "Read \(name): the skill rose \(raised) level(s)."
        default: ""
        }
    }
}
