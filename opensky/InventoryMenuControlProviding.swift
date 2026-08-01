// Main-app inventory menu seam (M12.2.2, issue #289). Keeps the verification
// panel independent of GameViewController while exposing the live menu-stack
// state, the engine-side row list, and the vanilla-movie presentation state
// behind it.
//
// Mirrors SystemMenuControlProviding deliberately: the two menus are the same
// kind of surface, and a reviewer who knows one should not have to learn a
// second shape.

import Foundation

nonisolated struct InventoryMenuControlSnapshot: Equatable {
    let isOpen: Bool
    /// Menu-stack identifiers currently open, top last. Proves the menu drives
    /// the engine's own stack rather than a private flag.
    let openMenus: [String]
    let worldSimPaused: Bool

    /// Engine-side list. Present whether or not the movie is up, so the menu
    /// is verifiable with no install-side movie at all.
    let categoryLabels: [String]
    let selectedCategoryIndex: Int
    /// One line per row of the selected category, already formatted.
    let entryLines: [String]
    let selectedIndex: Int
    let carriedWeight: Float
    let gold: Int32
    /// What the last equip, unequip or drop did, for the readout.
    let lastActionText: String?

    /// Vanilla presentation layer.
    let movieEnabled: Bool
    let movieLoaded: Bool
    let movieError: String?
    let movieDrawStats: SWFDrawStats
    let movieFaults: Int
    let movieMissingNames: Int
    let movieUnhandledInvokes: Int
    /// Row labels the movie's own list built for itself, read back out of
    /// `EntriesA`. These prove the engine's rows actually reached the movie.
    let movieEntryTitles: [String]
    let movieCategoryTitles: [String]
}

@MainActor
protocol InventoryMenuControlProviding: AnyObject {
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
    var inventoryMenuSnapshot: InventoryMenuControlSnapshot { get }
}
