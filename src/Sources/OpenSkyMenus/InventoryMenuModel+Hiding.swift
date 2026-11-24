// A list with some copies left out, such as the default apparel a follower's trade
// hides (UESP "Skyrim:Followers"). See docs/engine/barter.md#a-followers-trade.

import Foundation
public import OpenSkyFormatsESM

nonisolated extension InventoryMenuModel {
    /// The same list less `hidden` copies of each item. A row with no copy left goes.
    public func hiding(_ hidden: [FormID: Int32]) -> InventoryMenuModel {
        guard !hidden.isEmpty else { return self }
        let rows = allEntries.compactMap { entry -> InventoryMenuEntry? in
            let kept = hidden[entry.item] ?? 0
            let count = entry.count - kept
            guard count > 0 else { return nil }
            var row = InventoryMenuEntry(
                item: entry.item, name: entry.name, count: count, weight: entry.weight,
                value: entry.value, isEquipped: entry.isEquipped && kept == 0,
                family: entry.family, stolenCount: min(entry.stolenCount, count),
                isFood: entry.isFood, isFavourite: entry.isFavourite
            )
            row.isQuestItem = entry.isQuestItem
            row.hands = row.isEquipped ? entry.hands : []
            row.isMiscPotion = entry.isMiscPotion
            row.copy = entry.copy
            return row
        }
        return InventoryMenuModel(
            allEntries: rows, categories: categories, carriedWeight: carriedWeight, gold: gold
        )
    }

    /// The same list without worn rows, as a vendor's own side lists only what it does
    /// not wear.
    public var unworn: InventoryMenuModel {
        InventoryMenuModel(
            allEntries: allEntries.filter { !$0.isEquipped }, categories: categories,
            carriedWeight: carriedWeight, gold: gold
        )
    }

    /// This list and `other` as one, as a vendor's chest and its own inventory trade
    /// together: a row of the same item and copy adds its count, and the gold adds up.
    public func adding(_ other: InventoryMenuModel) -> InventoryMenuModel {
        var rows = allEntries
        for entry in other.allEntries {
            guard
                let index = rows
                    .firstIndex(where: { $0.item == entry.item && $0.copy == entry.copy })
            else {
                rows.append(entry)
                continue
            }
            let mine = rows[index]
            var row = InventoryMenuEntry(
                item: mine.item, name: mine.name, count: mine.count + entry.count,
                weight: mine.weight, value: mine.value, isEquipped: mine.isEquipped,
                family: mine.family, stolenCount: mine.stolenCount + entry.stolenCount,
                isFood: mine.isFood, isFavourite: mine.isFavourite
            )
            row.isQuestItem = mine.isQuestItem
            row.hands = mine.hands
            row.isMiscPotion = mine.isMiscPotion
            row.copy = mine.copy
            rows[index] = row
        }
        return InventoryMenuModel(
            allEntries: rows
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending },
            categories: categories, carriedWeight: carriedWeight,
            gold: Int32(clamping: Int64(gold) + Int64(other.gold))
        )
    }
}
