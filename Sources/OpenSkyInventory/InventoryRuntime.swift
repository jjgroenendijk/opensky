// Inventory accounting: the mutation API above `WorldStateStore`, plus carry
// weight and gold from item definitions. Every write goes through
// `WorldStateStore.set(_:for:in:)`. The arithmetic runs on the value type first,
// so a failed transfer or remove writes nothing.
// See docs/engine/inventory-state.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyWorldState

/// Reads and mutates inventories on top of a `WorldStateStore`.
@MainActor
public struct InventoryRuntime: InventoryAccess {
    /// `ItemDefinitionStore.vanillaGoldFormID`, kept here for callers that read it
    /// from the runtime.
    nonisolated public static let vanillaGoldFormID = ItemDefinitionStore.vanillaGoldFormID

    public let store: WorldStateStore
    public let baselines: InventoryBaselineResolver
    /// Which form counts as money. A settable property rather than a hardcoded
    /// constant, because a total-conversion load order need not use
    /// `Skyrim.esm`'s gold and the engine has no business assuming it does.
    public let goldFormID: FormID

    public init(
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
    public func inventory(of holder: InventoryHolder) -> ReferenceInventoryState {
        store.component(ReferenceInventoryState.self, for: holder.key)
            ?? baselines.baseline(for: holder.owner)
    }

    /// Whether `holder` has been touched at runtime, as opposed to still
    /// reading straight from plugin data.
    public func hasRuntimeInventory(_ holder: InventoryHolder) -> Bool {
        store.component(ReferenceInventoryState.self, for: holder.key) != nil
    }

    /// How many of `item` `holder` holds, honest and stolen copies together.
    public func count(of item: FormID, in holder: InventoryHolder) -> Int32 {
        inventory(of: holder).count(of: item)
    }

    /// How many stolen copies of `item` `holder` holds.
    public func stolenCount(of item: FormID, in holder: InventoryHolder) -> Int32 {
        inventory(of: holder).stolenCount(of: item)
    }

    /// Total weight `holder` carries. An unknown item adds nothing. Summed in
    /// `Double` to avoid rounding error on large stacks.
    public func carriedWeight(of holder: InventoryHolder) -> Float {
        let inventory = inventory(of: holder)
        let total = inventory.stacks.reduce(0.0) { running, stack in
            let weight = baselines.items.definition(stack.item)?.weight ?? 0
            return running + Double(weight) * Double(stack.count)
        }
        return Float(total)
    }

    /// Total gold value of everything `holder` carries, before barter adjustment.
    public func carriedValue(of holder: InventoryHolder) -> Int64 {
        inventory(of: holder).stacks.reduce(0) { running, stack in
            let value = baselines.items.definition(stack.item)?.value ?? 0
            return running + Int64(value) * Int64(stack.count)
        }
    }

    /// How much money `holder` has, which is just the size of its gold stack.
    public func goldCount(of holder: InventoryHolder) -> Int32 {
        count(of: goldFormID, in: holder)
    }

    // MARK: - Mutating

    /// Gives `holder` `count` more of `item`. The first write stores the whole
    /// baseline, so three lockpicks plus one stores four.
    /// - Returns: the inventory as stored afterwards.
    /// - Throws: `InventoryError.nonPositiveCount`, `InventoryError.countOverflow`.
    @discardableResult
    public func add(
        _ item: FormID,
        count: Int32,
        to holder: InventoryHolder,
        stolen: Bool = false
    ) throws -> ReferenceInventoryState {
        let updated = try inventory(of: holder)
            .adding(item, count: count, owner: holder.key, stolen: stolen)
        store.set(updated, for: holder.key, in: holder.cell)
        return updated
    }

    /// Removes `consumed` and adds `produced` on one holder in one write, so a
    /// craft or a harvest is all or nothing.
    /// - Throws: the inventory arithmetic errors; nothing is written then.
    @discardableResult
    public func apply(
        removing consumed: [InventoryStack],
        adding produced: [InventoryStack],
        on holder: InventoryHolder
    ) throws -> ReferenceInventoryState {
        var updated = inventory(of: holder)
        for stack in consumed {
            updated = try updated.removing(stack.item, count: stack.count, owner: holder.key)
        }
        for stack in produced {
            updated = try updated.adding(
                stack.item, count: stack.count, owner: holder.key, stolen: stack.stolen
            )
        }
        store.set(updated, for: holder.key, in: holder.cell)
        return updated
    }

    /// Takes `count` of `item` away from `holder`. Removing more than held is
    /// `InventoryError.insufficientCount` and writes nothing; it is not clamped.
    /// - Returns: the inventory as stored afterwards.
    /// - Throws: `InventoryError.nonPositiveCount`, `InventoryError.insufficientCount`.
    @discardableResult
    public func remove(_ item: FormID, count: Int32, from holder: InventoryHolder) throws
        -> ReferenceInventoryState
    {
        let updated = try inventory(of: holder).removing(item, count: count, owner: holder.key)
        store.set(updated, for: holder.key, in: holder.cell)
        return updated
    }

    /// Moves `count` of `item` from one owner to another, all or nothing, with two
    /// journal entries. The stolen split moves with the items; `markingStolen` marks
    /// all of it stolen, as taking from someone else's container does.
    /// - Throws: `InventoryError.sameHolder`, plus everything `add` and `remove` throw.
    public func transfer(
        _ item: FormID,
        count: Int32,
        from source: InventoryHolder,
        to destination: InventoryHolder,
        markingStolen: Bool = false
    ) throws {
        guard source.key != destination.key else {
            throw InventoryError.sameHolder(source.key)
        }
        let sourceInventory = inventory(of: source)
        let split = markingStolen
            ? StolenSplit(clean: 0, stolen: count)
            : sourceInventory.split(taking: count, of: item)
        let taken = try sourceInventory.removing(item, count: count, owner: source.key)
        let given = try inventory(of: destination)
            .adding(item, split: split, owner: destination.key)
        store.set(taken, for: source.key, in: source.cell)
        store.set(given, for: destination.key, in: destination.cell)
    }

    /// Moves items both ways at once: `first` gives `given` and receives `taken`, as
    /// a barter does. Both results are computed before either write, so a sale the
    /// merchant cannot pay for writes nothing. A zero leg is skipped. `laundering`
    /// makes both legs arrive honest, as a fence or vendor does.
    /// - Throws: `InventoryError.sameHolder`, plus the inventory arithmetic errors.
    public func exchange(
        giving given: (item: FormID, amount: Int32),
        taking taken: (item: FormID, amount: Int32),
        from first: InventoryHolder,
        to second: InventoryHolder,
        laundering: Bool = false
    ) throws {
        guard first.key != second.key else {
            throw InventoryError.sameHolder(first.key)
        }
        var giver = inventory(of: first)
        var receiver = inventory(of: second)
        // Each leg carries its own stolen split: hot goods stay hot, and the gold that
        // comes back is honest.
        if given.amount > 0 {
            let split = laundering
                ? StolenSplit(clean: given.amount, stolen: 0)
                : giver.split(taking: given.amount, of: given.item)
            giver = try giver.removing(given.item, count: given.amount, owner: first.key)
            receiver = try receiver.adding(given.item, split: split, owner: second.key)
        }
        if taken.amount > 0 {
            let split = laundering
                ? StolenSplit(clean: taken.amount, stolen: 0)
                : receiver.split(taking: taken.amount, of: taken.item)
            receiver = try receiver.removing(taken.item, count: taken.amount, owner: second.key)
            giver = try giver.adding(taken.item, split: split, owner: first.key)
        }
        store.set(giver, for: first.key, in: first.cell)
        store.set(receiver, for: second.key, in: second.cell)
    }

    /// Moves every stolen copy `source` holds into `destination`, still stolen, as
    /// an arrest does. All or nothing.
    /// - Returns: the stacks that moved, empty when nothing was stolen.
    /// - Throws: `InventoryError.sameHolder`, `InventoryError.countOverflow`.
    @discardableResult
    public func confiscateStolen(
        from source: InventoryHolder,
        to destination: InventoryHolder
    ) throws -> [InventoryStack] {
        guard source.key != destination.key else {
            throw InventoryError.sameHolder(source.key)
        }
        let (remaining, taken) = inventory(of: source).removingStolen()
        guard !taken.isEmpty else { return [] }
        var receiver = inventory(of: destination)
        for stack in taken {
            receiver = try receiver.adding(
                stack.item, count: stack.count, owner: destination.key, stolen: true
            )
        }
        store.set(remaining, for: source.key, in: source.cell)
        store.set(receiver, for: destination.key, in: destination.cell)
        return taken
    }

    // MARK: - Equipped set

    /// Marks `item` equipped on `holder`. Storage only; `EquipmentRuntime` handles
    /// slot conflicts.
    /// - Returns: true when the stored state changed.
    @discardableResult
    public func equip(_ item: FormID, on holder: InventoryHolder) -> Bool {
        store.set(inventory(of: holder).equipping(item), for: holder.key, in: holder.cell)
    }

    /// Marks `item` no longer equipped on `holder`.
    ///
    /// - Returns: true when the stored state changed.
    @discardableResult
    public func unequip(_ item: FormID, on holder: InventoryHolder) -> Bool {
        store.set(inventory(of: holder).unequipping(item), for: holder.key, in: holder.cell)
    }

    /// Replaces `holder`'s whole equipped set.
    ///
    /// - Returns: true when the stored state changed.
    @discardableResult
    public func setEquipped(_ items: [FormID], on holder: InventoryHolder) -> Bool {
        store.set(inventory(of: holder).settingEquipped(items), for: holder.key, in: holder.cell)
    }

    // MARK: - Reset

    /// Drops `holder`'s runtime inventory, so it re-derives from plugin data
    /// again. The component-level counterpart of `WorldStateStore.reset(_:)`.
    ///
    /// - Returns: true when a runtime inventory was actually removed.
    @discardableResult
    public func reset(_ holder: InventoryHolder) -> Bool {
        store.reset(.inventory, for: holder.key)
    }
}
