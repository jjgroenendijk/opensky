// Main-app inventory menu seam (M12.2.2, issue #289). Keeps the verification
// panel independent of GameViewController while exposing the live menu-stack
// state, the engine-side row list, and the vanilla-movie presentation state
// behind it.
//
// Mirrors SystemMenuControlProviding deliberately: the two menus are the same
// kind of surface, and a reviewer who knows one should not have to learn a
// second shape.

import Foundation

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
    /// One line per equipped item that carries an enchantment: what it is and how
    /// much charge is left (issue #472). Empty when nothing equipped is enchanted
    /// and when the session has no ENCH index.
    ///
    /// Beside the row list rather than inside it, because charge is a fact about
    /// the *equipped* item and the rows list everything carried; a stack of five
    /// unenchanted iron swords has no charge to show.
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
        movieCategoryTitles: [String]
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
    }
}

@MainActor
public protocol InventoryMenuControlProviding: AnyObject {
    var inventoryMenuIsOpen: Bool { get }
    /// Drives the vanilla `Interface\inventorymenu.swf` presentation layer. Off
    /// keeps the engine-side row list working with the gameplay HUD on screen.
    var inventoryMenuMovieEnabled: Bool { get set }
    func openInventoryMenu()
    func closeInventoryMenu()
    /// Routes one menu event through the same path as keyboard input, so the
    /// panel buttons and the live keys cannot diverge.
    func sendInventoryMenuInput(_ event: MenuInputEvent)
    /// Applies the selected row's action. Equip toggles, so a row that is
    /// already equipped unequips instead.
    func activateInventoryMenuSelection()
    func dropInventoryMenuSelection()
    /// Eats or drinks the selected row, removing one unit and applying its
    /// effects to the player (issue #469). A row that is not an ALCH or an
    /// INGR reports that and changes nothing.
    func consumeInventoryMenuSelection()
    var inventoryMenuSnapshot: InventoryMenuControlSnapshot { get }
}
