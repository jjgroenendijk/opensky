// Inventory accounting (issue #176, roadmap item 12.1.2): the mutation API
// above `WorldStateStore` and the arithmetic — carry weight and gold — that
// reads item definitions.
//
// A thin layer beside the store rather than methods on it. The store is the
// generic substrate that knows about keys, components, journalling and
// snapshots and deliberately knows nothing about records; inventory needs
// `ItemDefinitionStore` for weights and `InventoryBaselineResolver` for
// baselines, neither of which belongs inside it. Everything here writes through
// `WorldStateStore.set(_:for:in:)`, so every mutation lands in the journal, in
// the dirty counts and in the save exactly like a script's `Disable()` does.
//
// Headless and AppKit-free: this compiles into `openskycli` and is testable
// without a window. `@MainActor` only because the store it writes to is.
//
// Conservation: `transfer` computes both resulting inventories before writing
// either, so a transfer that cannot complete writes nothing at all and the
// total count across the two owners is unchanged. A failed `remove` leaves the
// store untouched for the same reason — the arithmetic happens on the value
// type first (`ReferenceInventoryState.removing`), and the store only ever sees
// a state that already succeeded.
//
// Documented in docs/engine/runtime-state.md.

import Foundation

/// One inventory owner: its identity, which plugin record its baseline comes
/// from, and the cell its mutations are attributed to.
///
/// The three travel together because every mutation needs all three, and
/// passing them separately at each call site is how a mutation ends up
/// attributed to the wrong cell. `cell` is optional for the same reason the
/// store's is: a script may empty a container in a cell that has never been
/// loaded.
nonisolated struct InventoryHolder: Equatable, Sendable {
    let key: ReferenceKey
    let owner: InventoryOwner
    let cell: CellSceneLocation?

    init(key: ReferenceKey, owner: InventoryOwner, cell: CellSceneLocation? = nil) {
        self.key = key
        self.owner = owner
        self.cell = cell
    }

    /// The player, whose baseline is empty and who belongs to no cell.
    static let player = InventoryHolder(key: .player, owner: .player, cell: nil)
}

/// Reads and mutates inventories on top of a `WorldStateStore`.
@MainActor
struct InventoryRuntime {
    /// Vanilla gold, `Gold001`.
    ///
    /// Gold is an ordinary `MISC` item and an ordinary stack — there is no
    /// separate currency field anywhere in this engine, which is also how the
    /// original data models it. Confirmed against the local install rather than
    /// from memory: `openskycli record Gold001` reports
    /// `MISC 0000000F — decoded MISC: editorID Gold001, value 1, weight 0.00`.
    /// Cross-checked against UESP "Skyrim:Gold".
    static let vanillaGoldFormID = FormID(0x0000_000F)

    let store: WorldStateStore
    let baselines: InventoryBaselineResolver
    /// Which form counts as money. A settable property rather than a hardcoded
    /// constant, because a total-conversion load order need not use
    /// `Skyrim.esm`'s gold and the engine has no business assuming it does.
    let goldFormID: FormID

    init(
        store: WorldStateStore,
        baselines: InventoryBaselineResolver,
        goldFormID: FormID = InventoryRuntime.vanillaGoldFormID
    ) {
        self.store = store
        self.baselines = baselines
        self.goldFormID = goldFormID
    }

    // MARK: - Reading

    /// `holder`'s effective inventory: its runtime component when it has one,
    /// its re-derived plugin baseline when it does not.
    func inventory(of holder: InventoryHolder) -> ReferenceInventoryState {
        store.component(ReferenceInventoryState.self, for: holder.key)
            ?? baselines.baseline(for: holder.owner)
    }

    /// Whether `holder` has been touched at runtime, as opposed to still
    /// reading straight from plugin data.
    func hasRuntimeInventory(_ holder: InventoryHolder) -> Bool {
        store.component(ReferenceInventoryState.self, for: holder.key) != nil
    }

    /// How many of `item` `holder` holds.
    func count(of item: FormID, in holder: InventoryHolder) -> Int32 {
        inventory(of: holder).count(of: item)
    }

    /// Total weight `holder` carries, from #175's per-item weights.
    ///
    /// An item no loaded plugin index describes contributes nothing, which is
    /// the only safe answer: guessing a weight for an unknown form would put a
    /// number the data never authored into an encumbrance check. Weight is
    /// summed in `Double` and returned as `Float` so a large stack does not
    /// accumulate rounding error one addition at a time.
    func carriedWeight(of holder: InventoryHolder) -> Float {
        let inventory = inventory(of: holder)
        let total = inventory.stacks.reduce(0.0) { running, stack in
            let weight = baselines.items.definition(stack.item)?.weight ?? 0
            return running + Double(weight) * Double(stack.count)
        }
        return Float(total)
    }

    /// Total gold value of everything `holder` carries, before any barter
    /// adjustment. Merchant pricing is issue #179.
    func carriedValue(of holder: InventoryHolder) -> Int64 {
        inventory(of: holder).stacks.reduce(0) { running, stack in
            let value = baselines.items.definition(stack.item)?.value ?? 0
            return running + Int64(value) * Int64(stack.count)
        }
    }

    /// How much money `holder` has, which is just the size of its gold stack.
    func goldCount(of holder: InventoryHolder) -> Int32 {
        count(of: goldFormID, in: holder)
    }

    // MARK: - Mutating

    /// Gives `holder` `count` more of `item`.
    ///
    /// The first mutation materializes the baseline into the component, so a
    /// container whose CNTO list holds three lockpicks and gains one ends up
    /// with a component holding four rather than a delta holding one.
    ///
    /// - Returns: the inventory as stored afterwards.
    /// - Throws: `InventoryError.nonPositiveCount`, `InventoryError.countOverflow`.
    @discardableResult
    func add(_ item: FormID, count: Int32, to holder: InventoryHolder) throws
        -> ReferenceInventoryState
    {
        let updated = try inventory(of: holder).adding(item, count: count, owner: holder.key)
        store.set(updated, for: holder.key, in: holder.cell)
        return updated
    }

    /// Takes `count` of `item` away from `holder`.
    ///
    /// Removing more than the owner holds is `InventoryError.insufficientCount`
    /// and writes nothing. It is deliberately not clamped: a caller that meant
    /// "take everything" can ask how much there is first, and one that did not
    /// mean it has a bug worth surfacing.
    ///
    /// - Returns: the inventory as stored afterwards.
    /// - Throws: `InventoryError.nonPositiveCount`, `InventoryError.insufficientCount`.
    @discardableResult
    func remove(_ item: FormID, count: Int32, from holder: InventoryHolder) throws
        -> ReferenceInventoryState
    {
        let updated = try inventory(of: holder).removing(item, count: count, owner: holder.key)
        store.set(updated, for: holder.key, in: holder.cell)
        return updated
    }

    /// Moves `count` of `item` from one owner to another.
    ///
    /// Both resulting inventories are computed before either is written, so the
    /// operation is all-or-nothing and the total count across the two owners is
    /// conserved. Two journal entries come out of it, one per owner, in source-
    /// then-destination order.
    ///
    /// - Throws: `InventoryError.sameHolder` when source and destination are
    ///   one owner, plus everything `add` and `remove` throw.
    func transfer(
        _ item: FormID,
        count: Int32,
        from source: InventoryHolder,
        to destination: InventoryHolder
    ) throws {
        guard source.key != destination.key else {
            throw InventoryError.sameHolder(source.key)
        }
        let taken = try inventory(of: source).removing(item, count: count, owner: source.key)
        let given = try inventory(of: destination)
            .adding(item, count: count, owner: destination.key)
        store.set(taken, for: source.key, in: source.cell)
        store.set(given, for: destination.key, in: destination.cell)
    }

    // MARK: - Equipped set

    /// Marks `item` equipped on `holder`. Storage only — slot conflicts and
    /// ARMA arbitration are issue #178.
    ///
    /// - Returns: true when the stored state changed.
    @discardableResult
    func equip(_ item: FormID, on holder: InventoryHolder) -> Bool {
        store.set(inventory(of: holder).equipping(item), for: holder.key, in: holder.cell)
    }

    /// Marks `item` no longer equipped on `holder`.
    ///
    /// - Returns: true when the stored state changed.
    @discardableResult
    func unequip(_ item: FormID, on holder: InventoryHolder) -> Bool {
        store.set(inventory(of: holder).unequipping(item), for: holder.key, in: holder.cell)
    }

    /// Replaces `holder`'s whole equipped set.
    ///
    /// - Returns: true when the stored state changed.
    @discardableResult
    func setEquipped(_ items: [FormID], on holder: InventoryHolder) -> Bool {
        store.set(inventory(of: holder).settingEquipped(items), for: holder.key, in: holder.cell)
    }

    // MARK: - Reset

    /// Drops `holder`'s runtime inventory, so it re-derives from plugin data
    /// again. The component-level counterpart of `WorldStateStore.reset(_:)`.
    ///
    /// - Returns: true when a runtime inventory was actually removed.
    @discardableResult
    func reset(_ holder: InventoryHolder) -> Bool {
        store.reset(.inventory, for: holder.key)
    }
}
