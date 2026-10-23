// Main-app container and barter menu seam: menu-stack state, the two-pane
// transfer list, barter pricing, and the merchant nomination. Shaped like
// `InventoryMenuControlProviding` on purpose.

import Foundation
import OpenSkyFormatsESM
import OpenSkyRendering

/// One container the readout can nominate as the merchant. Vanilla merchants sell
/// from a faction-linked chest, and that faction data is not decoded, so a
/// developer picks the container.
nonisolated public struct ContainerMenuMerchantOption: Equatable, Sendable {
    public let reference: FormID
    public let name: String
    /// How many individual items the container holds right now, so the readout
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
    /// In open pockets: the chance in percent to take, or place, the selected row.
    public var pickpocketChance: Int?
    /// The price factors in force and where their two GMSTs came from.
    public let priceFactor: Double
    public let pricingSource: String
    public let lastActionText: String?

    /// Containers the readout offers as merchants, and which one is nominated.
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
