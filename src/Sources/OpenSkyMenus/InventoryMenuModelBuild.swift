// Builds an `InventoryMenuModel` from a `ReferenceInventoryState` and an
// `ItemDefinitionStore`, so it is `nonisolated` and testable without a
// `WorldStateStore`. The `@MainActor` convenience is at the bottom.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface

nonisolated extension InventoryMenuModel {
    /// Builds one owner's list. Rows sort by name, then FormID, so the order is
    /// deterministic. Gold is left out: vanilla shows it as a readout, but
    /// `InventoryRuntime` stores it as a `MISC` stack. A non-playable item is left out too.
    public static func build(
        inventory: ReferenceInventoryState,
        items: ItemDefinitionStore,
        goldFormID: FormID = ItemDefinitionStore.vanillaGoldFormID,
        categories: [InventoryMenuCategory] = InventoryMenuCategory.engineOrder,
        favourites: FavouritesState = FavouritesState(),
        copies: InventoryMenuCopies = InventoryMenuCopies()
    ) -> InventoryMenuModel {
        var rows: [InventoryMenuEntry] = []
        var weight = 0.0
        // One row per item, not per stack. Stacks are keyed by (form, stolen),
        // and two rows with one name and FormID would look identical.
        var seen: Set<UInt32> = []
        for stack in inventory.stacks where seen.insert(stack.item.rawValue).inserted {
            let definition = items.definition(stack.item)
            let total = inventory.count(of: stack.item)
            weight += Double(definition?.weight ?? 0) * Double(total)
            guard stack.item != goldFormID, definition?.isPlayable != false else { continue }
            var row = InventoryMenuEntry(
                item: stack.item,
                name: name(of: stack.item, in: items),
                count: total,
                weight: definition?.weight ?? 0,
                value: items.gameValue(of: stack.item),
                isEquipped: inventory.isEquipped(stack.item),
                family: definition?.family,
                stolenCount: inventory.stolenCount(of: stack.item),
                isFood: items.ingestibles[stack.item.rawValue]?.flags.contains(.food) == true,
                isFavourite: favourites.contains(stack.item)
            )
            row.hands = heldHands(row, leftHand: inventory.leftHand)
            row.isMiscPotion = isMiscPotion(
                definition, isFood: row.isFood, keyword: items.miscPotionKeyword
            )
            let held = copies.state.copies(of: stack.item, held: total)
            rows += copies.rows(splitting: row, held: held)
        }
        return InventoryMenuModel(
            allEntries: rows.sorted(by: precedes),
            categories: categories,
            carriedWeight: Float(weight),
            gold: inventory.count(of: goldFormID)
        )
    }

    /// A potion that is not food, with the keyword the game files under Misc.
    static func isMiscPotion(
        _ definition: ItemDefinition?,
        isFood: Bool,
        keyword: FormID?
    ) -> Bool {
        guard let definition, definition.family == .ingestible, !isFood, let keyword else {
            return false
        }
        return definition.keywords.contains(keyword)
    }

    /// The left-hand item holds the left hand, or both with a second copy in the right.
    /// Any other worn weapon holds the right hand, a two-handed one too
    /// (docs/engine/unverified-values.md).
    static func heldHands(_ row: InventoryMenuEntry, leftHand: LeftHandHold?) -> HandSlots {
        guard row.isEquipped else { return [] }
        if let leftHand, leftHand.item == row.item {
            return leftHand.paired ? .bothHands : .leftHand
        }
        return row.family == .weapon ? .rightHand : []
    }

    /// FULL name, else editor ID, else the FormID — never empty, matching how
    /// `GameViewControllerItems.name(of:)` names a row.
    public static func name(of item: FormID, in items: ItemDefinitionStore) -> String {
        guard let definition = items.definition(item) else {
            return item.description
        }
        if case let .inline(value) = definition.name, !value.isEmpty {
            return value
        }
        return definition.editorID ?? item.description
    }

    private static func precedes(_ lhs: InventoryMenuEntry, _ rhs: InventoryMenuEntry) -> Bool {
        let ordering = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if ordering != .orderedSame {
            return ordering == .orderedAscending
        }
        return lhs.item.rawValue < rhs.item.rawValue
    }
}

/// Each owner's item copies and what one copy is worth, so a row can stand for a copy.
nonisolated public struct InventoryMenuCopies {
    public var state: ItemCopyState
    /// One copy's gold value; nil keeps the row's item value.
    public var value: ((FormID, ItemCopy) -> Int32)?

    public init(
        state: ItemCopyState = ItemCopyState(), value: ((FormID, ItemCopy) -> Int32)? = nil
    ) {
        self.state = state
        self.value = value
    }

    /// One row per kind of copy, best first, when the copies differ; else `row` alone.
    /// The best copy holds the equipped role, and stolen copies count from the plainest.
    func rows(splitting row: InventoryMenuEntry, held: [ItemCopy]) -> [InventoryMenuEntry] {
        var groups: [(copy: ItemCopy, count: Int32)] = []
        for copy in held.map(\.unchosen) {
            if let last = groups.last, last.copy == copy {
                groups[groups.count - 1].count += 1
            } else {
                groups.append((copy, 1))
            }
        }
        guard groups.count > 1 || groups.first.map({ !$0.copy.isPlain }) == true
        else { return [row] }
        var stolen = row.stolenCount
        var split: [InventoryMenuEntry] = []
        for (index, group) in groups.enumerated().reversed() {
            let mine = min(stolen, group.count)
            stolen -= mine
            var entry = InventoryMenuEntry(
                item: row.item, name: group.copy.name ?? row.name, count: group.count,
                weight: row.weight, value: value?(row.item, group.copy) ?? row.value,
                isEquipped: row.isEquipped && index == 0, family: row.family,
                stolenCount: mine, isFood: row.isFood, isFavourite: row.isFavourite
            )
            entry.isQuestItem = row.isQuestItem
            entry.hands = index == 0 ? row.hands : []
            entry.isMiscPotion = row.isMiscPotion
            entry.copy = group.copy
            split.insert(entry, at: 0)
        }
        return split
    }
}

@MainActor
extension InventoryMenuModel {
    /// The live model for `holder`, read through the runtime that owns both the
    /// stored inventory and the definitions behind it.
    public static func build(
        holder: InventoryHolder,
        runtime: any InventoryAccess,
        categories: [InventoryMenuCategory] = InventoryMenuCategory.engineOrder,
        favourites: FavouritesState = FavouritesState()
    ) -> InventoryMenuModel {
        build(
            inventory: runtime.inventory(of: holder),
            items: runtime.baselines.items,
            goldFormID: runtime.goldFormID,
            categories: categories,
            favourites: favourites,
            copies: copies(of: holder, runtime: runtime)
        )
    }

    /// Every held copy of each item `holder` carries, with the runtime's copy values.
    static func copies(of holder: InventoryHolder, runtime: any InventoryAccess)
        -> InventoryMenuCopies
    {
        let items = Set(runtime.inventory(of: holder).stacks.map(\.item))
        let state = ItemCopyState(copies: Dictionary(uniqueKeysWithValues: items.map {
            ($0.rawValue, runtime.copies(of: $0, in: holder))
        }))
        return InventoryMenuCopies(state: state) { runtime.value(of: $0, copy: $1) }
    }
}
