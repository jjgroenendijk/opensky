// Main-app container and barter menu seam (M12.2.3, issue #179). Keeps the
// verification panel independent of GameViewController while exposing the live
// menu-stack state, the two-pane transfer list, the resolved barter pricing and
// the merchant nomination.
//
// Mirrors InventoryMenuControlProviding deliberately: the three menus are the
// same kind of surface, and a reviewer who knows one should not have to learn a
// third shape.

import Foundation

/// One container the panel can nominate as the merchant.
///
/// There is no merchant system yet — vanilla merchants sell from a
/// faction-linked chest, and none of that faction data is decoded — so the
/// milestone's merchant is a container reference a developer picks. This is the
/// seam that nomination goes through, and it is what a faction-driven answer
/// replaces later without the menu changing.
nonisolated struct ContainerMenuMerchantOption: Equatable, Sendable {
    let reference: FormID
    let name: String
    /// How many individual items the container holds right now, so the panel
    /// can tell a stocked chest from an empty one before opening it.
    let itemCount: Int
    let gold: Int32
}

nonisolated struct ContainerMenuControlSnapshot: Equatable {
    let isOpen: Bool
    /// Menu-stack identifiers currently open, top last.
    let openMenus: [String]
    let worldSimPaused: Bool

    let mode: ContainerMenuModel.Mode
    let side: ContainerMenuModel.Side
    /// What activating the selected row would do: Take, Store, Buy or Sell.
    let transferLabel: String
    /// The container or merchant this session is against, or nil when none is
    /// open.
    let containerName: String?
    /// One line per row of the active side, already formatted.
    let entryLines: [String]
    let selectedIndex: Int
    let categoryLabels: [String]
    let selectedCategoryIndex: Int
    let playerGold: Int32
    let containerGold: Int32
    /// What the selected row costs, or nil in container mode.
    let selectedPrice: Int32?
    /// Whether the paying side can cover `selectedPrice`.
    let canAffordSelection: Bool
    /// The price factors in force and where their two GMSTs came from.
    let priceFactor: Double
    let pricingSource: String
    let lastActionText: String?

    /// Containers the panel offers as merchants, and which one is nominated.
    let merchantOptions: [ContainerMenuMerchantOption]
    let selectedMerchant: FormID?

    /// Vanilla presentation layer.
    let movieEnabled: Bool
    let movieLoaded: Bool
    let movieError: String?
    let movieDrawStats: SWFDrawStats
    let movieFaults: Int
    let movieMissingNames: Int
    let movieUnhandledInvokes: Int
    /// Row labels the movie's own list built for itself, read back out of
    /// `EntriesA`, which is what proves the engine's rows reached the movie.
    let movieEntryTitles: [String]
    /// The merchant purse the movie is drawing, read back off its own vendor
    /// gold field. Nil in container mode, where the field is not placed.
    let movieVendorGold: String?
}

@MainActor
protocol ContainerMenuControlProviding: AnyObject {
    var containerMenuIsOpen: Bool { get }
    /// Container transfer or merchant barter. Changing it while the menu is
    /// open reopens it against the other movie, because the two menus are two
    /// movies rather than two states of one.
    var containerMenuMode: ContainerMenuModel.Mode { get set }
    /// Drives the vanilla movie. Off keeps the engine-side list working with
    /// the gameplay HUD on screen.
    var containerMenuMovieEnabled: Bool { get set }
    func openContainerMenu()
    func closeContainerMenu()
    /// Routes one menu event through the same path as keyboard input.
    func sendContainerMenuInput(_ event: MenuInputEvent)
    /// Swaps which owner's items the list shows.
    func switchContainerMenuSide()
    /// Takes, stores, buys or sells the selected row, according to the mode and
    /// the side. A refusal — nothing stocked, nobody can pay — lands in the
    /// readout rather than throwing.
    func activateContainerMenuSelection()
    func takeAllFromContainerMenu()

    // MARK: - Merchant nomination

    /// Resident containers the panel can nominate.
    var containerMenuMerchantOptions: [ContainerMenuMerchantOption] { get }
    /// Nominates one as the active merchant. The returned text is what the
    /// readout shows, including the reason a nomination was refused.
    @discardableResult
    func selectContainerMenuMerchant(_ reference: FormID) -> String
    /// Nominates whatever container the crosshair is on, which is the path a
    /// developer standing in front of a chest actually uses.
    @discardableResult
    func selectContainerMenuMerchantFromInteraction() -> String

    var containerMenuSnapshot: ContainerMenuControlSnapshot { get }
}
