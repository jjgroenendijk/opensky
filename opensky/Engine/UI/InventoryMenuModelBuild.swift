// Building an `InventoryMenuModel` from stored inventory (M12.2.2, issue #289).
// Satellite of UI/InventoryMenuModel.swift, split out so the value type stays
// readable beside the arithmetic that fills it.
//
// The builder takes the two inputs plainly — a `ReferenceInventoryState` and an
// `ItemDefinitionStore` — rather than an `InventoryRuntime`, so it is
// `nonisolated` and testable without a `WorldStateStore`. The `@MainActor`
// convenience that pulls both out of a live runtime is at the bottom.

import Foundation

nonisolated extension InventoryMenuModel {
    /// Builds the list one owner presents.
    ///
    /// Rows sort by display name, case-insensitively, then by FormID so two
    /// items sharing a name still order deterministically — a menu whose row
    /// order changes between two identical states is untestable.
    ///
    /// The gold stack is excluded from the rows: vanilla shows money as a
    /// readout, not as a takeable row, and `InventoryRuntime` models it as an
    /// ordinary `MISC` stack, so it would otherwise appear twice.
    static func build(
        inventory: ReferenceInventoryState,
        items: ItemDefinitionStore,
        goldFormID: FormID = InventoryRuntime.vanillaGoldFormID,
        categories: [InventoryMenuCategory] = InventoryMenuCategory.engineOrder
    ) -> InventoryMenuModel {
        var rows: [InventoryMenuEntry] = []
        var weight = 0.0
        for stack in inventory.stacks {
            let definition = items.definition(stack.item)
            weight += Double(definition?.weight ?? 0) * Double(stack.count)
            guard stack.item != goldFormID else { continue }
            rows.append(
                InventoryMenuEntry(
                    item: stack.item,
                    name: name(of: stack.item, in: items),
                    count: stack.count,
                    weight: definition?.weight ?? 0,
                    value: definition?.value ?? 0,
                    isEquipped: inventory.isEquipped(stack.item),
                    family: definition?.family
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
    static func name(of item: FormID, in items: ItemDefinitionStore) -> String {
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
    static func build(
        holder: InventoryHolder,
        runtime: InventoryRuntime,
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
