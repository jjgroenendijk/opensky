// Main-app container and barter menu seam (M12.2.3, issue #179). Keeps the
// verification panel independent of GameViewController while exposing the live
// menu-stack state, the two-pane transfer list, the resolved barter pricing and
// the merchant nomination.
//
// Mirrors InventoryMenuControlProviding deliberately: the three menus are the
// same kind of surface, and a reviewer who knows one should not have to learn a
// third shape.

import Foundation
import OpenSkyFormats

/// One container the panel can nominate as the merchant.
///
/// There is no merchant system yet — vanilla merchants sell from a
/// faction-linked chest, and none of that faction data is decoded — so the
/// milestone's merchant is a container reference a developer picks. This is the
/// seam that nomination goes through, and it is what a faction-driven answer
/// replaces later without the menu changing.
nonisolated public struct ContainerMenuMerchantOption: Equatable, Sendable {
    public let reference: FormID
    public let name: String
    /// How many individual items the container holds right now, so the panel
    /// can tell a stocked chest from an empty one before opening it.
    public let itemCount: Int
    public let gold: Int32

    public init(reference: FormID, name: String, itemCount: Int, gold: Int32) {
        self.reference = reference
        self.name = name
        self.itemCount = itemCount
        self.gold = gold
    }
}

nonisolated public struct ContainerMenuControlSnapshot: Equatable, Sendable {
    public let isOpen: Bool
    /// Menu-stack identifiers currently open, top last.
    public let openMenus: [String]
    public let worldSimPaused: Bool

    public let mode: ContainerMenuModel.Mode
    public let side: ContainerMenuModel.Side
    /// What activating the selected row would do: Take, Store, Buy or Sell.
    public let transferLabel: String
    /// The container or merchant this session is against, or nil when none is
    /// open.
    public let containerName: String?
    /// One line per row of the active side, already formatted.
    public let entryLines: [String]
    public let selectedIndex: Int
    public let categoryLabels: [String]
    public let selectedCategoryIndex: Int
    public let playerGold: Int32
    public let containerGold: Int32
    /// What the selected row costs, or nil in container mode.
    public let selectedPrice: Int32?
    /// Whether the paying side can cover `selectedPrice`.
    public let canAffordSelection: Bool
    /// The price factors in force and where their two GMSTs came from.
    public let priceFactor: Double
    public let pricingSource: String
    public let lastActionText: String?

    /// Containers the panel offers as merchants, and which one is nominated.
    public let merchantOptions: [ContainerMenuMerchantOption]
    public let selectedMerchant: FormID?

    /// Vanilla presentation layer.
    public let movieEnabled: Bool
    public let movieLoaded: Bool
    public let movieError: String?
    public let movieDrawStats: SWFDrawStats
    public let movieFaults: Int
    public let movieMissingNames: Int
    public let movieUnhandledInvokes: Int
    /// Row labels the movie's own list built for itself, read back out of
    /// `EntriesA`, which is what proves the engine's rows reached the movie.
    public let movieEntryTitles: [String]
    /// The merchant purse the movie is drawing, read back off its own vendor
    /// gold field. Nil in container mode, where the field is not placed.
    public let movieVendorGold: String?

    public init(
        isOpen: Bool,
        openMenus: [String],
        worldSimPaused: Bool,
        mode: ContainerMenuModel.Mode,
        side: ContainerMenuModel.Side,
        transferLabel: String,
        containerName: String?,
        entryLines: [String],
        selectedIndex: Int,
        categoryLabels: [String],
        selectedCategoryIndex: Int,
        playerGold: Int32,
        containerGold: Int32,
        selectedPrice: Int32?,
        canAffordSelection: Bool,
        priceFactor: Double,
        pricingSource: String,
        lastActionText: String?,
        merchantOptions: [ContainerMenuMerchantOption],
        selectedMerchant: FormID?,
        movieEnabled: Bool,
        movieLoaded: Bool,
        movieError: String?,
        movieDrawStats: SWFDrawStats,
        movieFaults: Int,
        movieMissingNames: Int,
        movieUnhandledInvokes: Int,
        movieEntryTitles: [String],
        movieVendorGold: String?
    ) {
        self.isOpen = isOpen
        self.openMenus = openMenus
        self.worldSimPaused = worldSimPaused
        self.mode = mode
        self.side = side
        self.transferLabel = transferLabel
        self.containerName = containerName
        self.entryLines = entryLines
        self.selectedIndex = selectedIndex
        self.categoryLabels = categoryLabels
        self.selectedCategoryIndex = selectedCategoryIndex
        self.playerGold = playerGold
        self.containerGold = containerGold
        self.selectedPrice = selectedPrice
        self.canAffordSelection = canAffordSelection
        self.priceFactor = priceFactor
        self.pricingSource = pricingSource
        self.lastActionText = lastActionText
        self.merchantOptions = merchantOptions
        self.selectedMerchant = selectedMerchant
        self.movieEnabled = movieEnabled
        self.movieLoaded = movieLoaded
        self.movieError = movieError
        self.movieDrawStats = movieDrawStats
        self.movieFaults = movieFaults
        self.movieMissingNames = movieMissingNames
        self.movieUnhandledInvokes = movieUnhandledInvokes
        self.movieEntryTitles = movieEntryTitles
        self.movieVendorGold = movieVendorGold
    }
}

@MainActor
public protocol ContainerMenuControlProviding: AnyObject {
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
