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
        store.component(ReferenceInventoryState.self, for: holder.key) ?? baseline(of: holder)
    }

    /// `holder`'s plugin inventory, rolled at the level its cell froze.
    public func baseline(of holder: InventoryHolder) -> ReferenceInventoryState {
        baselines.baseline(of: holder, frozenLevel: store.frozenLeveledLevel(of: holder.key))
    }

    /// The roll `holder`'s leveled lists take: its own when placed, else its base's.
    public func roll(of holder: InventoryHolder) -> LeveledRoll {
        baselines.roll(of: holder, frozenLevel: store.frozenLeveledLevel(of: holder.key))
            ?? baselines.leveling.roll(forActor: InventoryBaselineResolver.playerBase)
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
            let value = baselines.items.gameValue(of: stack.item)
            return running + Int64(value) * Int64(stack.count)
        }
    }

    /// How much money `holder` has, which is just the size of its gold stack.
    public func goldCount(of holder: InventoryHolder) -> Int32 {
        count(of: goldFormID, in: holder)
    }

    // MARK: - Mutating

    /// Gives `holder` `count` more of `item`. The first write stores the whole
    /// baseline, so three lockpicks plus one stores four. `copies` are the copies
    /// among them that differ from the record; the rest arrive plain.
    /// - Returns: the inventory as stored afterwards.
    /// - Throws: `InventoryError.nonPositiveCount`, `InventoryError.countOverflow`.
    @discardableResult
    public func add(
        _ item: FormID,
        count: Int32,
        to holder: InventoryHolder,
        stolen: Bool = false,
        copies: [ItemCopy] = []
    ) throws -> ReferenceInventoryState {
        let before = inventory(of: holder)
        let updated = try before.adding(item, count: count, owner: holder.key, stolen: stolen)
        store.set(updated, for: holder.key, in: holder.cell)
        recopy(item, in: holder, before: before.count(of: item), arriving: copies)
        return updated
    }

    /// `add` for an item that was not stolen, as `InventoryAccess` asks it.
    @discardableResult
    public func add(
        _ item: FormID,
        count: Int32,
        to holder: InventoryHolder
    ) throws -> ReferenceInventoryState {
        try add(item, count: count, to: holder, stolen: false)
    }

    /// Removes `consumed` and adds `produced` on one holder in one write, so a
    /// craft or a harvest is all or nothing. `usingUp` spends stolen copies
    /// first, so a craft clears the stolen mark of what it uses.
    /// - Throws: the inventory arithmetic errors; nothing is written then.
    @discardableResult
    public func apply(
        removing consumed: [InventoryStack],
        adding produced: [InventoryStack],
        on holder: InventoryHolder,
        usingUp: Bool = false
    ) throws -> ReferenceInventoryState {
        let before = inventory(of: holder)
        var updated = before
        for stack in consumed {
            updated = try updated.removing(
                stack.item, count: stack.count, owner: holder.key, stolenFirst: usingUp
            )
        }
        for stack in produced {
            updated = try updated.adding(
                stack.item, count: stack.count, owner: holder.key, stolen: stack.stolen
            )
        }
        store.set(updated, for: holder.key, in: holder.cell)
        for stack in consumed {
            recopy(
                stack.item, in: holder, before: before.count(of: stack.item), taken: stack.count
            )
        }
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
        let before = inventory(of: holder)
        let updated = try before.removing(item, count: count, owner: holder.key)
        store.set(updated, for: holder.key, in: holder.cell)
        recopy(item, in: holder, before: before.count(of: item), taken: count)
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
        let destinationInventory = inventory(of: destination)
        let given = try destinationInventory.adding(item, split: split, owner: destination.key)
        let moving = leavingCopies(count, of: item, in: source)
        store.set(taken, for: source.key, in: source.cell)
        store.set(given, for: destination.key, in: destination.cell)
        recopy(item, in: source, before: sourceInventory.count(of: item), taken: count)
        recopy(
            item, in: destination, before: destinationInventory.count(of: item), arriving: moving
        )
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
        let (giverBefore, receiverBefore) = (inventory(of: first), inventory(of: second))
        var giver = giverBefore
        var receiver = receiverBefore
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
        let givenCopies = leavingCopies(max(0, given.amount), of: given.item, in: first)
        let takenCopies = leavingCopies(max(0, taken.amount), of: taken.item, in: second)
        store.set(giver, for: first.key, in: first.cell)
        store.set(receiver, for: second.key, in: second.cell)
        if given.amount > 0 {
            moveCopies(
                givenCopies, of: given.item,
                from: (first, giverBefore), to: (second, receiverBefore)
            )
        }
        if taken.amount > 0 {
            moveCopies(
                takenCopies, of: taken.item,
                from: (second, receiverBefore), to: (first, giverBefore)
            )
        }
    }

    /// The quality half of one exchange leg, with each side's inventory before the leg.
    private func moveCopies(
        _ copies: [ItemCopy],
        of item: FormID,
        from source: (holder: InventoryHolder, before: ReferenceInventoryState),
        to destination: (holder: InventoryHolder, before: ReferenceInventoryState)
    ) {
        recopy(
            item, in: source.holder, before: source.before.count(of: item),
            taken: Int32(copies.count)
        )
        recopy(
            item, in: destination.holder, before: destination.before.count(of: item),
            arriving: copies
        )
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
        let sourceBefore = inventory(of: source)
        let (remaining, taken) = sourceBefore.removingStolen()
        guard !taken.isEmpty else { return [] }
        let receiverBefore = inventory(of: destination)
        var receiver = receiverBefore
        for stack in taken {
            receiver = try receiver.adding(
                stack.item, count: stack.count, owner: destination.key, stolen: true
            )
        }
        let moving = taken.map { leavingCopies($0.count, of: $0.item, in: source) }
        store.set(remaining, for: source.key, in: source.cell)
        store.set(receiver, for: destination.key, in: destination.cell)
        for (stack, moved) in zip(taken, moving) {
            moveCopies(
                moved, of: stack.item,
                from: (source, sourceBefore), to: (destination, receiverBefore)
            )
        }
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
