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
    /// An `ALCH` with the food flag, which the Food tab takes instead of Potions.
    public let isFood: Bool
    public let isFavourite: Bool
    /// The number key 1 to 8 bound to the item, if any.
    public let hotkey: Int?

    public init(
        item: FormID,
        name: String,
        count: Int32,
        weight: Float,
        value: Int32,
        isEquipped: Bool,
        family: ItemDefinition.Family?,
        stolenCount: Int32 = 0,
        isFood: Bool = false,
        isFavourite: Bool = false,
        hotkey: Int? = nil
    ) {
        self.item = item
        self.name = name
        self.count = count
        self.weight = weight
        self.value = value
        self.isEquipped = isEquipped
        self.family = family
        self.stolenCount = stolenCount
        self.isFood = isFood
        self.isFavourite = isFavourite
        self.hotkey = hotkey
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
    /// Splits `ALCH` rows: true takes only food, false only potions, nil both.
    public let food: Bool?
    /// The Favorites tab, which takes the marked rows of any family.
    public let favourites: Bool

    public init(
        label: String, families: Set<ItemDefinition.Family>, food: Bool? = nil,
        favourites: Bool = false
    ) {
        self.label = label
        self.families = families
        self.food = food
        self.favourites = favourites
    }

    /// Whether `entry` belongs in this category. An empty family set is the
    /// "All" tab and takes everything.
    public func accepts(_ entry: InventoryMenuEntry) -> Bool {
        guard !favourites else { return entry.isFavourite }
        guard !families.isEmpty else { return true }
        guard food == nil || food == entry.isFood else { return false }
        return families.contains(entry.family ?? .miscellaneous)
    }

    /// The tabs in the game's order, named by `texts`. Only the player's own inventory
    /// has a Favorites tab.
    public static func tabs(
        texts: InventoryMenuTexts, favourites: Bool = false
    ) -> [InventoryMenuCategory] {
        func tab(
            _ tab: InventoryMenuTexts.Tab, _ families: Set<ItemDefinition.Family>,
            food: Bool? = nil
        ) -> InventoryMenuCategory {
            InventoryMenuCategory(label: texts.label(tab), families: families, food: food)
        }
        let favouritesTab = InventoryMenuCategory(
            label: texts.label(.favorites), families: [], favourites: true
        )
        return (favourites ? [favouritesTab] : []) + [
            tab(.all, []),
            tab(.weapons, [.weapon, .ammunition]),
            tab(.apparel, [.armor]),
            tab(.potions, [.ingestible], food: false),
            tab(.scrolls, [.scroll]),
            tab(.food, [.ingestible], food: true),
            tab(.ingredients, [.ingredient]),
            tab(.books, [.book]),
            tab(.keys, [.key]),
            tab(.misc, [.miscellaneous, .soulGem, .apparatus])
        ]
    }

    public static let engineOrder = tabs(texts: .vanilla)
}

/// The whole list one owner presents: its categories, the rows inside the
/// selected one, and the two totals the vanilla menu keeps on screen.
nonisolated public struct InventoryMenuModel: Equatable, Sendable {
    /// Every row the owner carries, before category filtering, sorted by name.
    public let allEntries: [InventoryMenuEntry]
    public let categories: [InventoryMenuCategory]
    public private(set) var selectedCategoryIndex: Int
    public private(set) var selectedIndex: Int
    /// Total carried weight across every row. The app sets the perk-adjusted total.
    public var carriedWeight: Float
    /// The owner's gold, which is an ordinary stack rather than a currency
    /// field — see `ItemDefinitionStore.vanillaGoldFormID`.
    public let gold: Int32
    /// Open while the player picks how many of a stack to drop.
    public var quantity: InventoryQuantityPrompt?

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
        // The menu opens on All, not on the Favorites tab before it.
        selectedCategoryIndex = categories.firstIndex { $0.families.isEmpty && !$0.favourites }
            ?? 0
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

/// The quantity slider: how many of one stack the next drop moves.
nonisolated public struct InventoryQuantityPrompt: Equatable, Sendable {
    public let item: FormID
    public let name: String
    public let maximum: Int32
    /// What the count is for: "Drop", "Take", "Store", "Buy", or "Sell".
    public let verb: String
    /// Starts at the whole stack, as the movie's `ShowQuantityMenu` sets it.
    public private(set) var value: Int32

    /// `InventoryDefines.QUANTITY_MENU_COUNT_LIMIT` in the vanilla movie: a stack of
    /// at most this many drops one without asking.
    public static let countLimit: Int32 = 5

    /// The prompt a move of `count` copies opens, or nil when it moves one at once.
    public static func asking(
        item: FormID, name: String, count: Int32, verb: String = "Drop"
    ) -> Self? {
        count > countLimit ? Self(item: item, name: name, maximum: count, verb: verb) : nil
    }

    public init(item: FormID, name: String, maximum: Int32, verb: String = "Drop") {
        self.item = item
        self.name = name
        self.maximum = max(1, maximum)
        self.verb = verb
        value = self.maximum
    }

    /// Moves the count by `step`, kept between 1 and the stack.
    public mutating func adjust(by step: Int32) {
        value = min(max(1, value &+ step), maximum)
    }

    public var text: String {
        "\(verb) how many \(name)? \(value) of \(maximum)"
    }
}
