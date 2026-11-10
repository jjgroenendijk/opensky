// Fakes of the spellbook seams: the known spells per holder in a set, every cast recorded.

public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface
public import OpenSkyMagicInterface

@MainActor
public final class FakeSpellbookAccess: SpellbookAccess {
    public var spells = SpellStore(plugins: [])
    public var known: [ReferenceKey: Set<ReferenceKey>] = [:]

    public init() {}

    public func state(of holder: ActorValueHolder) -> SpellbookState {
        SpellbookState(known: (known[holder.key] ?? []).sorted())
    }

    public func record(_: ReferenceKey) -> ResolvedSpell? {
        nil
    }

    public func learn(_ spell: ReferenceKey, on holder: ActorValueHolder) -> Bool {
        known[holder.key, default: []].insert(spell).inserted
    }

    public func forget(_ spell: ReferenceKey, on holder: ActorValueHolder) -> Bool {
        known[holder.key]?.remove(spell) != nil
    }

    public func equip(
        _ spell: ReferenceKey,
        in _: SpellHand,
        on _: ActorValueHolder,
        inventory _: InventoryHolder?
    ) throws -> SpellEquipChange {
        throw SpellbookError.unknownSpell(spell: spell)
    }

    public func unequip(_: SpellHand, on _: ActorValueHolder) -> ReferenceKey? {
        nil
    }
}

@MainActor
public final class FakeSpellCaster: SpellCasting {
    public let spellbook = FakeSpellbookAccess()

    public var spellbookAccess: any SpellbookAccess {
        spellbook
    }

    public init() {}

    public func apply(_: ResolvedSpell, caster _: ActorValueHolder) -> Int {
        0
    }
}
