// A list with some copies left out, such as the default apparel a follower's trade
// hides (UESP "Skyrim:Followers"). See docs/engine/barter.md#a-followers-trade.

import OpenSkyFormatsESM

nonisolated extension InventoryMenuModel {
    /// The same list less `hidden` copies of each item. A row with no copy left goes.
    public func hiding(_ hidden: [FormID: Int32]) -> InventoryMenuModel {
        guard !hidden.isEmpty else { return self }
        let rows = allEntries.compactMap { entry -> InventoryMenuEntry? in
            let kept = hidden[entry.item] ?? 0
            let count = entry.count - kept
            guard count > 0 else { return nil }
            return InventoryMenuEntry(
                item: entry.item, name: entry.name, count: count, weight: entry.weight,
                value: entry.value, isEquipped: entry.isEquipped && kept == 0,
                family: entry.family, stolenCount: min(entry.stolenCount, count),
                isFood: entry.isFood, isFavourite: entry.isFavourite
            )
        }
        return InventoryMenuModel(
            allEntries: rows, categories: categories, carriedWeight: carriedWeight, gold: gold
        )
    }
}
