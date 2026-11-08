public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface
public import OpenSkyMagicInterface

/// What the world adapters use of `SpellbookRuntime`.
public protocol SpellbookRuntimePort {
    @discardableResult func equip(
        _ spell: ReferenceKey,
        in hand: SpellHand,
        on holder: ActorValueHolder,
        inventory: InventoryHolder?
    ) throws -> SpellEquipChange
    func knownSpells(of holder: ActorValueHolder) -> [ResolvedSpell]
    var spells: SpellStore { get }

    func occupancy(of spell: ResolvedSpell, in hand: SpellHand) -> HandSlots?
    func record(_ spell: ReferenceKey) -> ResolvedSpell?
}

/// The default arguments a protocol requirement cannot carry.
extension SpellbookRuntimePort {
    @discardableResult public func equip(
        _ spell: ReferenceKey,
        in hand: SpellHand,
        on holder: ActorValueHolder
    ) throws -> SpellEquipChange {
        try equip(spell, in: hand, on: holder, inventory: nil)
    }
}
