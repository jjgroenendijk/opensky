import Foundation
public import OpenSkyMagicInterface

nonisolated extension MagicEffectActionOutcome {
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

nonisolated extension CastingActionOutcome {
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
}
