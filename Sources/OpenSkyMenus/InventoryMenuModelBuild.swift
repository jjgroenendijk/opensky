// Builds an `InventoryMenuModel` from a `ReferenceInventoryState` and an
// `ItemDefinitionStore`, so it is `nonisolated` and testable without a
// `WorldStateStore`. The `@MainActor` convenience is at the bottom.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface

nonisolated extension InventoryMenuModel {
    /// Builds one owner's list. Rows sort by name, then FormID, so the order is
    /// deterministic. Gold is left out: vanilla shows it as a readout, but
    /// `InventoryRuntime` stores it as a `MISC` stack.
    public static func build(
        inventory: ReferenceInventoryState,
        items: ItemDefinitionStore,
        goldFormID: FormID = ItemDefinitionStore.vanillaGoldFormID,
        categories: [InventoryMenuCategory] = InventoryMenuCategory.engineOrder
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
            guard stack.item != goldFormID else { continue }
            rows.append(
                InventoryMenuEntry(
                    item: stack.item,
                    name: name(of: stack.item, in: items),
                    count: total,
                    weight: definition?.weight ?? 0,
                    value: definition?.value ?? 0,
                    isEquipped: inventory.isEquipped(stack.item),
                    family: definition?.family,
                    stolenCount: inventory.stolenCount(of: stack.item)
                )
            )
        }
        return InventoryMenuModel(
            allEntries: rows.sorted(by: precedes),
            categories: categories,
            carriedWeight: Float(weight),
            gold: inventory.count(of: goldFormID)
        )
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

@MainActor
extension InventoryMenuModel {
    /// The live model for `holder`, read through the runtime that owns both the
    /// stored inventory and the definitions behind it.
    public static func build(
        holder: InventoryHolder,
        runtime: any InventoryAccess,
        categories: [InventoryMenuCategory] = InventoryMenuCategory.engineOrder
    ) -> InventoryMenuModel {
        build(
            inventory: runtime.inventory(of: holder),
            items: runtime.baselines.items,
            goldFormID: runtime.goldFormID,
            categories: categories
        )
    }
}
