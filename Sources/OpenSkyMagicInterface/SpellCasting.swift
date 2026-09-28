// The seams scripts reach spells through. `CasterRuntime` and `SpellbookRuntime`
// conform, and the composition root hands them over as these protocols.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface

/// The spells an actor knows and holds ready.
@MainActor
public protocol SpellbookAccess {
    /// Every spell the load order carries.
    var spells: SpellStore { get }

    /// `holder`'s known and readied spells.
    func state(of holder: ActorValueHolder) -> SpellbookState

    /// The resolved SPEL behind `spell`, or nil when this load order does not
    /// carry it.
    func record(_ spell: ReferenceKey) -> ResolvedSpell?

    /// Teaches `holder` one spell. Returns true when it was not already known.
    @discardableResult
    func learn(_ spell: ReferenceKey, on holder: ActorValueHolder) -> Bool

    /// Removes one spell. Returns true when it was known.
    @discardableResult
    func forget(_ spell: ReferenceKey, on holder: ActorValueHolder) -> Bool

    /// Readies `spell` in `hand`, displacing whatever held that hand.
    ///
    /// - Throws: `SpellbookError` when the spell cannot be readied there.
    @discardableResult
    func equip(
        _ spell: ReferenceKey,
        in hand: SpellHand,
        on holder: ActorValueHolder,
        inventory: InventoryHolder?
    ) throws -> SpellEquipChange

    /// Empties `hand`. Returns the spell that was readied there.
    @discardableResult
    func unequip(_ hand: SpellHand, on holder: ActorValueHolder) -> ReferenceKey?
}

extension SpellbookAccess {
    /// Readies `spell` in `hand` with no inventory to clear the hand in.
    @discardableResult
    public func equip(
        _ spell: ReferenceKey,
        in hand: SpellHand,
        on holder: ActorValueHolder
    ) throws -> SpellEquipChange {
        try equip(spell, in: hand, on: holder, inventory: nil)
    }
}

/// Casting a spell on behalf of a script.
@MainActor
public protocol SpellCasting: AnyObject {
    /// The spellbook this caster reads.
    var spellbookAccess: any SpellbookAccess { get }

    /// Delivers one application of `spell`. Returns how many timed effects
    /// were stored.
    func apply(_ spell: ResolvedSpell, caster: ActorValueHolder) -> Int
}
