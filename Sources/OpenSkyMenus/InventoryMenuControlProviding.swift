// Inventory menu seam: menu-stack state, engine rows, and movie state, without
// exposing `GameViewController`. Same shape as `SystemMenuControlProviding`.

import Foundation
import OpenSkyRendering

nonisolated public struct InventoryMenuControlSnapshot: Equatable, Sendable {
    public let isOpen: Bool
    /// Menu-stack identifiers currently open, top last. Proves the menu drives
    /// the engine's own stack rather than a private flag.
    public let openMenus: [String]
    public let worldSimPaused: Bool

    /// Engine-side list. Present whether or not the movie is up, so the menu
    /// is verifiable with no install-side movie at all.
    public let categoryLabels: [String]
    public let selectedCategoryIndex: Int
    /// One line per row of the selected category, already formatted.
    public let entryLines: [String]
    public let selectedIndex: Int
    public let carriedWeight: Float
    public let gold: Int32
    /// What the last equip, unequip or drop did, for the readout.
    public let lastActionText: String?
    /// One line per equipped enchanted item with its remaining charge. Empty
    /// without an ENCH index. Outside the rows because charge belongs to the
    /// equipped item, not the stack.
    public let enchantmentLines: [String]

    /// Vanilla presentation layer.
    public let movieEnabled: Bool
    public let movieLoaded: Bool
    public let movieError: String?
    public let movieDrawStats: SWFDrawStats
    public let movieFaults: Int
    public let movieMissingNames: Int
    public let movieUnhandledInvokes: Int
    /// Row labels the movie's own list built for itself, read back out of
    /// `EntriesA`. These prove the engine's rows actually reached the movie.
    public let movieEntryTitles: [String]
    public let movieCategoryTitles: [String]
    public let extras: InventoryMenuExtras

    public init(
        isOpen: Bool,
        openMenus: [String],
        worldSimPaused: Bool,
        categoryLabels: [String],
        selectedCategoryIndex: Int,
        entryLines: [String],
        selectedIndex: Int,
        carriedWeight: Float,
        gold: Int32,
        lastActionText: String?,
        enchantmentLines: [String],
        movieEnabled: Bool,
        movieLoaded: Bool,
        movieError: String?,
        movieDrawStats: SWFDrawStats,
        movieFaults: Int,
        movieMissingNames: Int,
        movieUnhandledInvokes: Int,
        movieEntryTitles: [String],
        movieCategoryTitles: [String],
        extras: InventoryMenuExtras = .none
    ) {
        self.isOpen = isOpen
        self.openMenus = openMenus
        self.worldSimPaused = worldSimPaused
        self.categoryLabels = categoryLabels
        self.selectedCategoryIndex = selectedCategoryIndex
        self.entryLines = entryLines
        self.selectedIndex = selectedIndex
        self.carriedWeight = carriedWeight
        self.gold = gold
        self.lastActionText = lastActionText
        self.enchantmentLines = enchantmentLines
        self.movieEnabled = movieEnabled
        self.movieLoaded = movieLoaded
        self.movieError = movieError
        self.movieDrawStats = movieDrawStats
        self.movieFaults = movieFaults
        self.movieMissingNames = movieMissingNames
        self.movieUnhandledInvokes = movieUnhandledInvokes
        self.movieEntryTitles = movieEntryTitles
        self.movieCategoryTitles = movieCategoryTitles
        self.extras = extras
    }
}

/// The item card, the quantity slider, the favourites, and the turning preview.
nonisolated public struct InventoryMenuExtras: Equatable, Sendable {
    public static let none = Self(
        itemCard: [], quantity: nil, hotkeys: [], previewEnabled: false, previewLine: nil
    )

    /// The selected row's card, one line each.
    public let itemCard: [String]
    /// The open quantity prompt's line.
    public let quantity: String?
    /// One line per bound slot, such as "1: Iron Sword".
    public let hotkeys: [String]
    public let previewEnabled: Bool
    /// The preview's model and turn, or why it shows nothing.
    public let previewLine: String?

    public init(
        itemCard: [String], quantity: String?, hotkeys: [String], previewEnabled: Bool,
        previewLine: String?
    ) {
        self.itemCard = itemCard
        self.quantity = quantity
        self.hotkeys = hotkeys
        self.previewEnabled = previewEnabled
        self.previewLine = previewLine
    }
}
