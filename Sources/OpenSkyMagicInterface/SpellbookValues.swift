import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// Failures readying a spell reports. Like `EquipmentError`, each is a caller
/// mistake or a data answer, never malformed input.
nonisolated public enum SpellbookError: Error, Equatable {
    /// The actor does not know the spell it was asked to ready.
    case notKnown(spell: ReferenceKey, actor: ReferenceKey)
    /// No loaded plugin carries the spell at all.
    case unknownSpell(spell: ReferenceKey)
    /// The spell's ETYP resolves to a slot that takes no hand — Voice, which is
    /// what a shout and a lesser power carry — so there is nothing for readying
    /// it in a hand to mean.
    case notHandEquippable(spell: ReferenceKey)
    /// The spell's ETYP is a choose-one slot that does not offer the requested
    /// hand. Refused rather than quietly readied elsewhere.
    case handUnavailable(spell: ReferenceKey, hand: SpellHand)
}

/// What one readying changed.
nonisolated public struct SpellEquipChange: Equatable, Sendable {
    /// The hands it now fills, which is both for a two-handed spell whichever
    /// hand was asked for.
    public let hands: HandSlots
    /// Spells displaced out of those hands, in ascending key order.
    public let unequippedSpells: [ReferenceKey]
    /// Worn items displaced out of those hands, in ascending FormID order.
    public let unequippedItems: [FormID]

    public init(
        hands: HandSlots,
        unequippedSpells: [ReferenceKey],
        unequippedItems: [FormID]
    ) {
        self.hands = hands
        self.unequippedSpells = unequippedSpells
        self.unequippedItems = unequippedItems
    }
}
