// The engine-side inventory list, grouped by the categories
// `inventorymenu.swf` filters by (docs/engine/inventory-menu.md). The movie
// bridge and the sidebar both read it, so they cannot disagree.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// One item row: the stack plus everything the row displays.
///
/// The name is resolved once, here, rather than at each display site — a row
/// whose form no loaded plugin describes still names something (see
/// `InventoryMenuModel.name(of:in:)`), and a menu must never render an empty
/// row.
nonisolated public struct InventoryMenuEntry: Equatable, Sendable {
    public let item: FormID
    public let name: String
    public let count: Int32
    /// Per-item weight, not the stack total. The movie's row shows the unit
    /// weight beside the count, and the stack total is a sum the readout does.
    public let weight: Float
    /// Per-item gold value, likewise before multiplying by `count`.
    public let value: Int32
    public let isEquipped: Bool
    /// The record family the item came from, or nil when no loaded plugin
    /// describes the form. A nil family lands in `.miscellaneous` for
    /// filtering, because dropping the row entirely would hide an item the
    /// player is genuinely carrying.
    public let family: ItemDefinition.Family?
    /// How many of `count` are stolen. Honest and stolen copies share one row,
    /// because two identical rows could not be told apart.
    public let stolenCount: Int32

    public init(
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
    public var isStolen: Bool {
        stolenCount > 0
    }

    public var totalWeight: Float {
        weight * Float(count)
    }

    public var totalValue: Int64 {
        Int64(value) * Int64(count)
    }
}

/// One tab of the category list, grouped by `ItemDefinition.Family`. The
/// movie's own `InventoryDefines` constants are read from the loaded movie,
/// never reproduced here.
nonisolated public struct InventoryMenuCategory: Equatable, Sendable {
    public let label: String
    public let families: Set<ItemDefinition.Family>

    /// Whether `entry` belongs in this category. An empty family set is the
    /// "All" tab and takes everything.
    public func accepts(_ entry: InventoryMenuEntry) -> Bool {
        guard !families.isEmpty else { return true }
        return families.contains(entry.family ?? .miscellaneous)
    }

    /// The tabs the menu presents, in order. One tab per decoded family group,
    /// plus the leading "All" tab; a family OpenSky does not decode yet cannot
    /// appear, which is why the list is derived from `Family` rather than
    /// mirroring the vanilla tab strip position for position.
    public static let engineOrder: [InventoryMenuCategory] = [
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
nonisolated public struct InventoryMenuModel: Equatable, Sendable {
    /// Every row the owner carries, before category filtering, sorted by name.
    public let allEntries: [InventoryMenuEntry]
    public let categories: [InventoryMenuCategory]
    public private(set) var selectedCategoryIndex: Int
    public private(set) var selectedIndex: Int
    /// Total carried weight across every row.
    public let carriedWeight: Float
    /// The owner's gold, which is an ordinary stack rather than a currency
    /// field — see `ItemDefinitionStore.vanillaGoldFormID`.
    public let gold: Int32

    public static let empty = InventoryMenuModel(
        allEntries: [], categories: [], carriedWeight: 0, gold: 0
    )

    public init(
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
    public var entries: [InventoryMenuEntry] {
        guard categories.indices.contains(selectedCategoryIndex) else {
            return allEntries
        }
        return allEntries.filter(categories[selectedCategoryIndex].accepts)
    }

    public var selectedEntry: InventoryMenuEntry? {
        let rows = entries
        guard rows.indices.contains(selectedIndex) else { return nil }
        return rows[selectedIndex]
    }

    public var categoryLabels: [String] {
        categories.map(\.label)
    }

    // MARK: - Navigation

    /// Moves the row selection by `offset`, clamped rather than wrapped: a
    /// vanilla list stops at its ends, and wrapping past the last row is how a
    /// held key silently returns to the top.
    public mutating func moveSelection(by offset: Int) {
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
    public mutating func moveCategory(by offset: Int) {
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

    public mutating func selectCategory(_ index: Int) {
        guard categories.indices.contains(index) else { return }
        selectedCategoryIndex = index
        selectedIndex = 0
    }

    public mutating func select(_ index: Int) {
        guard entries.indices.contains(index) else { return }
        selectedIndex = index
    }
}
