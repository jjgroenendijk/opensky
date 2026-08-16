// Knowing spells and readying them (issue #470, roadmap item 19.7): the
// mutation layer over `SpellbookState`, plus the arbitration that keeps a
// readied spell and a worn weapon from claiming the same hand.
//
// A thin layer beside `WorldStateStore`, following `InventoryRuntime`,
// `ActorValueRuntime` and `ActiveEffectRuntime`. Every mutation writes through
// `WorldStateStore.set`, so it lands in the journal, in the dirty counts and in
// the save exactly like a take or a drop does.
//
// ## Why this is not `EquipmentRuntime`
//
// `EquipmentRuntime.equip` refuses to equip anything the owner does not hold,
// and that refusal is load-bearing: "silently equipping an item out of nowhere
// is how a duplication bug hides". A spell is never held. It has no stack, no
// weight, no `EquippableItem` entry, and it cannot be dropped, sold or given
// away. Widening `equip` to accept a FormID nobody holds would remove the guard
// for every caller in order to serve the one caller that legitimately needs it.
//
// So spells get their own component and their own equip path, and the two meet
// where they actually collide: hands. `EquipmentOccupancy` and `HandSlots` are
// shared, `EquipmentChange` is what both report, and this type arbitrates both
// directions — readying a spell unequips the weapon or shield whose hand it
// takes, and `equipItem` unequips the spell whose hand a weapon takes. That
// second direction is why the item path routes through here rather than calling
// `EquipmentRuntime.equip` directly.
//
// Headless and AppKit-free: this compiles into `openskycli` and is testable
// without a window. `@MainActor` only because the store it writes to is.
//
// Documented in docs/engine/magic.md and docs/engine/inventory-equipment.md.

import Foundation

/// Failures readying a spell reports. Like `EquipmentError`, each is a caller
/// mistake or a data answer, never malformed input.
nonisolated enum SpellbookError: Error, Equatable {
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
nonisolated struct SpellEquipChange: Equatable, Sendable {
    let spell: ReferenceKey
    /// The hands it now fills, which is both for a two-handed spell whichever
    /// hand was asked for.
    let hands: HandSlots
    /// Spells displaced out of those hands, in ascending key order.
    let unequippedSpells: [ReferenceKey]
    /// Worn items displaced out of those hands, in ascending FormID order.
    let unequippedItems: [FormID]
    /// False when the spell was already readied in exactly these hands and
    /// nothing was displaced, so the stored state is byte-identical.
    let changed: Bool
}

/// Reads and mutates spellbooks on top of a `WorldStateStore`.
@MainActor
struct SpellbookRuntime {
    let store: WorldStateStore
    /// Load-order SPEL and SCRL lookup behind every stored key.
    let spells: SpellStore
    /// EQUP graph the ETYP links resolve through.
    let equipSlots: EquipSlotStore
    /// The worn-equipment layer, so a readied spell and a weapon cannot claim
    /// the same hand. Nil in a session with no item index, and then readying a
    /// spell arbitrates against other spells only.
    let equipment: EquipmentRuntime?

    init(
        store: WorldStateStore,
        spells: SpellStore,
        equipSlots: EquipSlotStore,
        equipment: EquipmentRuntime? = nil
    ) {
        self.store = store
        self.spells = spells
        self.equipSlots = equipSlots
        self.equipment = equipment
    }

    // MARK: - Reading

    /// `holder`'s spellbook, empty when nothing has ever written one.
    func state(of holder: ActorValueHolder) -> SpellbookState {
        store.component(SpellbookState.self, for: holder.key) ?? SpellbookState()
    }

    func knows(_ spell: ReferenceKey, _ holder: ActorValueHolder) -> Bool {
        state(of: holder).knows(spell)
    }

    /// The record behind a stored key, or nil when this load order no longer
    /// carries it.
    func record(_ spell: ReferenceKey) -> ResolvedSpell? {
        spells.spell(key: spell)
    }

    /// Every spell `holder` knows that this load order can still resolve, in
    /// key order. A key the load order dropped stays in the component — losing
    /// it would make removing a plugin destroy progress — and is simply absent
    /// from this listing.
    func knownSpells(of holder: ActorValueHolder) -> [ResolvedSpell] {
        state(of: holder).known.compactMap(record)
    }

    /// What readying `spell` in `hand` would occupy, or nil when it cannot be
    /// readied there at all.
    func occupancy(of spell: ResolvedSpell, in hand: SpellHand) -> HandSlots? {
        equipSlots
            .handChoice(of: spell.record.equipType, fromPlugin: spell.sourcePlugin)?
            .occupancy(preferring: hand.slots)
    }

    // MARK: - Knowing

    /// Teaches `holder` one spell.
    ///
    /// - Returns: true when the spell was not already known.
    @discardableResult
    func learn(_ spell: ReferenceKey, on holder: ActorValueHolder) -> Bool {
        write(state(of: holder).learning(spell), for: holder)
    }

    /// Grants the spells the player starts knowing, plus anything `additional`
    /// names — which is where an actor's own `SPLO` list arrives.
    ///
    /// - Returns: how many were not already known.
    @discardableResult
    func grantStartSpells(
        to holder: ActorValueHolder,
        additional: [ReferenceKey] = []
    ) -> Int {
        grant(spells.playerStartSpells.map(\.key) + additional, to: holder)
    }

    /// Teaches a whole list at once, in one write.
    ///
    /// - Returns: how many were not already known.
    @discardableResult
    func grant(_ list: [ReferenceKey], to holder: ActorValueHolder) -> Int {
        var state = state(of: holder)
        var granted = 0
        for spell in list where !state.knows(spell) {
            state = state.learning(spell)
            granted += 1
        }
        write(state, for: holder)
        return granted
    }

    /// One actor's authored spell list — its `SPLO` run — as runtime keys.
    ///
    /// A link is kept only when this load order carries a record behind it.
    /// Plugin-relative resolution alone is not enough: it answers with an
    /// identity for any FormID whose plugin is loaded, whether or not a SPEL
    /// with that object ID exists, so a dangling `SPLO` entry would otherwise
    /// become a known spell nothing can ever name.
    ///
    /// That is the opposite of the rule for a *stored* known spell, which is
    /// kept even when it no longer resolves — removing a plugin must not
    /// destroy progress. The difference is direction: this is reading a link
    /// out of a record now, not restoring one the player earned earlier.
    func resolve(_ list: [FormID], fromPlugin pluginName: String) -> [ReferenceKey] {
        list.compactMap { spells.resolve($0, fromPlugin: pluginName)?.key }
    }

    /// Removes one spell, and with it any hand that was holding it.
    ///
    /// - Returns: true when the spell was known.
    @discardableResult
    func forget(_ spell: ReferenceKey, on holder: ActorValueHolder) -> Bool {
        write(state(of: holder).forgetting(spell), for: holder)
    }

    // MARK: - Reading a tome

    /// Opens `book` as `holder`.
    ///
    /// The cited rule is the mark, not the removal. UESP documents BOOK DATA
    /// flag `0x08` as "Read ... flag in save game data for already read books?"
    /// and states the teaching rule as "Spell Tomes: opening the book for the
    /// first time teaches you a spell"
    /// (<https://en.uesp.net/wiki/Skyrim:Books>). Neither source says the tome
    /// leaves the inventory, so this does not take it — see
    /// docs/engine/magic.md, which records the gap rather than guessing at it.
    ///
    /// - Returns: what the reading did.
    @discardableResult
    func read(
        book: ReferenceKey,
        teaching spell: ReferenceKey?,
        on holder: ActorValueHolder
    ) -> SpellTomeReading {
        let before = state(of: holder)
        guard !before.hasRead(book) else {
            return SpellTomeReading(book: book, spell: spell, taught: false, alreadyRead: true)
        }
        var after = before.markingRead(book)
        var taught = false
        if let spell, spells.spell(key: spell) != nil, !after.knows(spell) {
            after = after.learning(spell)
            taught = true
        }
        write(after, for: holder)
        return SpellTomeReading(book: book, spell: spell, taught: taught, alreadyRead: false)
    }

    // MARK: - Readying

    /// Readies `spell` in `hand`, displacing whatever held that hand.
    ///
    /// - Throws: `SpellbookError` when the actor does not know the spell, when
    ///   this load order does not carry it, or when its ETYP cannot put it in
    ///   the requested hand.
    @discardableResult
    func equip(
        _ spell: ReferenceKey,
        in hand: SpellHand,
        on holder: ActorValueHolder,
        inventory: InventoryHolder? = nil
    ) throws -> SpellEquipChange {
        let state = state(of: holder)
        guard state.knows(spell) else {
            throw SpellbookError.notKnown(spell: spell, actor: holder.key)
        }
        guard let record = record(spell) else {
            throw SpellbookError.unknownSpell(spell: spell)
        }
        guard
            let choice = equipSlots.handChoice(
                of: record.record.equipType,
                fromPlugin: record.sourcePlugin
            ),
            !choice.candidates.isEmpty
        else {
            throw SpellbookError.notHandEquippable(spell: spell)
        }
        guard let hands = choice.occupancy(preferring: hand.slots) else {
            throw SpellbookError.handUnavailable(spell: spell, hand: hand)
        }
        let displacedSpells = Set(SpellHand.allCases.compactMap { candidate in
            hands.contains(candidate.slots) ? state.spell(in: candidate) : nil
        }.filter { $0 != spell })
        let displacedItems = unequipItems(occupying: hands, inventory: inventory)
        let changed = write(state.equipping(spell, in: hands), for: holder)
        return SpellEquipChange(
            spell: spell,
            hands: hands,
            unequippedSpells: displacedSpells.sorted(),
            unequippedItems: displacedItems,
            changed: changed || !displacedItems.isEmpty
        )
    }

    /// Empties `hand` of whatever spell it holds. Emptying a hand that holds no
    /// spell changes nothing and is not an error, matching
    /// `EquipmentRuntime.unequip`.
    ///
    /// - Returns: the spell that was readied there, or nil when there was none.
    @discardableResult
    func unequip(_ hand: SpellHand, on holder: ActorValueHolder) -> ReferenceKey? {
        let state = state(of: holder)
        guard let spell = state.spell(in: hand) else { return nil }
        write(state.unequipping(hand.slots), for: holder)
        return spell
    }

    /// Equips a worn item, first emptying every hand a readied spell holds that
    /// the item would need.
    ///
    /// The item path routes through here rather than calling
    /// `EquipmentRuntime.equip` directly, because that layer knows nothing
    /// about spells and would leave a sword and a spell both claiming the right
    /// hand.
    @discardableResult
    func equipItem(
        _ item: FormID,
        on holder: ActorValueHolder,
        inventory: InventoryHolder
    ) throws -> EquipmentChange {
        guard let equipment else {
            throw EquipmentError.notEquippable(item: item)
        }
        let hands = equipment.occupancy(of: item).hands
        if !hands.isEmpty {
            let state = state(of: holder)
            if state.occupiedHands.overlaps(hands) {
                write(state.unequipping(hands), for: holder)
            }
        }
        return try equipment.equip(item, on: inventory)
    }

    // MARK: - Powers

    /// Marks `power` spent on whole game day `day`.
    func spendPower(_ power: ReferenceKey, onDay day: Int32, on holder: ActorValueHolder) {
        write(state(of: holder).spendingPower(power, onDay: day), for: holder)
    }

    // MARK: - Private

    /// Unequips every worn item occupying `hands`, reporting what it took off.
    ///
    /// Empty without an equipment runtime or without an inventory holder to act
    /// on, which is the synthetic-session case: spells then arbitrate against
    /// spells and nothing else, and the panel says so.
    private func unequipItems(
        occupying hands: HandSlots,
        inventory: InventoryHolder?
    ) -> [FormID] {
        guard let equipment, let inventory, !hands.isEmpty else { return [] }
        let doomed = equipment.equipped(on: inventory)
            .filter { equipment.occupancy(of: $0).hands.overlaps(hands) }
            .sorted { $0.rawValue < $1.rawValue }
        for item in doomed {
            equipment.unequip(item, on: inventory)
        }
        return doomed
    }

    /// Stores `state`, dropping the whole component once it is empty so an
    /// actor that knows no spells stops being dirty for this slot.
    ///
    /// - Returns: true when the stored state changed.
    @discardableResult
    private func write(_ state: SpellbookState, for holder: ActorValueHolder) -> Bool {
        guard state != self.state(of: holder) else { return false }
        if state.isEmpty {
            store.reset(.spellbook, for: holder.key)
        } else {
            store.set(state, for: holder.key, in: holder.cell)
        }
        return true
    }
}

/// What opening one book did.
nonisolated struct SpellTomeReading: Equatable, Sendable {
    let book: ReferenceKey
    /// The SPEL the book's DATA names, or nil when it teaches no spell.
    let spell: ReferenceKey?
    /// True when this reading added the spell to the reader's spellbook.
    let taught: Bool
    /// True when the reader had already opened this book, which is the state
    /// the "Read" mark exists to answer.
    let alreadyRead: Bool
}
