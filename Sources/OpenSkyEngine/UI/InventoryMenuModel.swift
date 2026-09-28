// The engine-side inventory list (M12.2.2, issue #289): one owner's items
// reduced to what a menu row needs, grouped into the categories the vanilla
// `inventorymenu.swf` filters by.
//
// This type is the single source of the list. The vanilla presentation layer
// (UI/InventoryMenuMovieBridge.swift) pushes it into the movie's `EntriesA` and
// `_CategoriesList`, and the sidebar panel prints the same rows, so the movie
// and the verification readout cannot disagree about what the player carries.
//
// Device-free, AppKit-free and free of any renderer, so it builds into
// `openskycli` and is unit-testable against a synthetic `ItemDefinitionStore`.
//
// Documented in docs/engine/inventory-menu.md.

import Foundation

/// One item row: the stack plus everything the row displays.
///
/// The name is resolved once, here, rather than at each display site — a row
/// whose form no loaded plugin describes still names something (see
/// `InventoryMenuModel.name(of:in:)`), and a menu must never render an empty
/// row.
nonisolated struct InventoryMenuEntry: Equatable, Sendable {
    let item: FormID
    let name: String
    let count: Int32
    /// Per-item weight, not the stack total. The movie's row shows the unit
    /// weight beside the count, and the stack total is a sum the readout does.
    let weight: Float
    /// Per-item gold value, likewise before multiplying by `count`.
    let value: Int32
    let isEquipped: Bool
    /// The record family the item came from, or nil when no loaded plugin
    /// describes the form. A nil family lands in `.miscellaneous` for
    /// filtering, because dropping the row entirely would hide an item the
    /// player is genuinely carrying.
    let family: ItemDefinition.Family?
    /// How many of `count` were taken from somebody who owned them (issue
    /// #504). A row is one *item*, honest and stolen copies together, because
    /// two rows with the same name and FormID would be two identical-looking
    /// controls the player could not tell apart; the marker says how many of
    /// them are hot.
    let stolenCount: Int32

    init(
        item: FormID,
        name: String,
        count: Int32,
        weight: Float,
        value: Int32,
        isEquipped: Bool,
        family: ItemDefinition.Family?,
        stolenCount: Int32 = 0
    ) {
        self.item = item
        self.name = name
        self.count = count
        self.weight = weight
        self.value = value
        self.isEquipped = isEquipped
        self.family = family
        self.stolenCount = stolenCount
    }

    /// Whether any copy in this row is stolen, which is what the "Stolen"
    /// marker shows. "As long as this tag is present, the item is considered
    /// stolen" (<https://en.uesp.net/wiki/Skyrim:Crime>).
    var isStolen: Bool {
        stolenCount > 0
    }

    var totalWeight: Float {
        weight * Float(count)
    }

    var totalValue: Int64 {
        Int64(value) * Int64(count)
    }
}

/// One tab of the category list.
///
/// The grouping is over `ItemDefinition.Family`, which is OpenSky's own decode
/// of the record types #175 reads, rather than a guess at Bethesda's internal
/// category numbering. The vanilla movie's own `InventoryDefines` constants are
/// read back off the loaded movie where they are needed, never reproduced here
/// from memory — see `InventoryMenuMovieBridge`.
nonisolated struct InventoryMenuCategory: Equatable, Sendable {
    let label: String
    let families: Set<ItemDefinition.Family>

    /// Whether `entry` belongs in this category. An empty family set is the
    /// "All" tab and takes everything.
    func accepts(_ entry: InventoryMenuEntry) -> Bool {
        guard !families.isEmpty else { return true }
        return families.contains(entry.family ?? .miscellaneous)
    }

    /// The tabs the menu presents, in order. One tab per decoded family group,
    /// plus the leading "All" tab; a family OpenSky does not decode yet cannot
    /// appear, which is why the list is derived from `Family` rather than
    /// mirroring the vanilla tab strip position for position.
    static let engineOrder: [InventoryMenuCategory] = [
        InventoryMenuCategory(label: "All", families: []),
        InventoryMenuCategory(label: "Weapons", families: [.weapon, .ammunition]),
        InventoryMenuCategory(label: "Armor", families: [.armor]),
        InventoryMenuCategory(label: "Potions", families: [.ingestible]),
        InventoryMenuCategory(label: "Ingredients", families: [.ingredient]),
        InventoryMenuCategory(label: "Books", families: [.book]),
        InventoryMenuCategory(label: "Misc", families: [.miscellaneous])
    ]
}

/// The whole list one owner presents: its categories, the rows inside the
/// selected one, and the two totals the vanilla menu keeps on screen.
nonisolated struct InventoryMenuModel: Equatable, Sendable {
    /// Every row the owner carries, before category filtering, sorted by name.
    let allEntries: [InventoryMenuEntry]
    let categories: [InventoryMenuCategory]
    private(set) var selectedCategoryIndex: Int
    private(set) var selectedIndex: Int
    /// Total carried weight across every row, from #175's per-item weights.
    let carriedWeight: Float
    /// The owner's gold, which is an ordinary stack rather than a currency
    /// field — see `InventoryRuntime.vanillaGoldFormID`.
    let gold: Int32

    static let empty = InventoryMenuModel(
        allEntries: [], categories: [], carriedWeight: 0, gold: 0
    )

    init(
        allEntries: [InventoryMenuEntry],
        categories: [InventoryMenuCategory],
        carriedWeight: Float,
        gold: Int32
    ) {
        self.allEntries = allEntries
        self.categories = categories
        self.carriedWeight = carriedWeight
        self.gold = gold
        selectedCategoryIndex = 0
        selectedIndex = 0
    }

    // MARK: - Reading

    /// The rows the selected category shows, which is what the movie's
    /// `EntriesA` is filled from.
    var entries: [InventoryMenuEntry] {
        guard categories.indices.contains(selectedCategoryIndex) else {
            return allEntries
        }
        return allEntries.filter(categories[selectedCategoryIndex].accepts)
    }

    var selectedEntry: InventoryMenuEntry? {
        let rows = entries
        guard rows.indices.contains(selectedIndex) else { return nil }
        return rows[selectedIndex]
    }

    var categoryLabels: [String] {
        categories.map(\.label)
    }

    // MARK: - Navigation

    /// Moves the row selection by `offset`, clamped rather than wrapped: a
    /// vanilla list stops at its ends, and wrapping past the last row is how a
    /// held key silently returns to the top.
    mutating func moveSelection(by offset: Int) {
        let rows = entries.count
        guard rows > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(max(selectedIndex + offset, 0), rows - 1)
    }

    /// Switches category by `offset` and returns the row selection to the top —
    /// the new category's rows are a different list, so keeping the old index
    /// would land on an unrelated item.
    ///
    /// Wraps, so holding "next category" cycles the tabs rather than sticking
    /// at the last one.
    mutating func moveCategory(by offset: Int) {
        let count = categories.count
        guard count > 0 else {
            selectedCategoryIndex = 0
            selectedIndex = 0
            return
        }
        let raw = (selectedCategoryIndex + offset) % count
        selectedCategoryIndex = raw < 0 ? raw + count : raw
        selectedIndex = 0
    }

    mutating func selectCategory(_ index: Int) {
        guard categories.indices.contains(index) else { return }
        selectedCategoryIndex = index
        selectedIndex = 0
    }

    mutating func select(_ index: Int) {
        guard entries.indices.contains(index) else { return }
        selectedIndex = index
    }
}
