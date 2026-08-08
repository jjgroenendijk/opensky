// The container/barter-menu half of the world-provider fake (issue #179), in
// its own file so `FakeWorldProviders` stays inside the lint caps. Stored state
// lives on the class; everything here is behaviour.
//
// The two lists are deliberately different so a test can tell which side the
// panel is showing without inspecting the model.

@testable import opensky

extension FakeWorldProviders {
    static let merchantList = InventoryMenuModel(
        allEntries: [
            InventoryMenuEntry(
                item: FormID(0x0200), name: "IronSword", count: 1, weight: 9, value: 25,
                isEquipped: false, family: .weapon
            )
        ],
        categories: InventoryMenuCategory.engineOrder,
        carriedWeight: 9,
        gold: 500
    )

    static let playerList = InventoryMenuModel(
        allEntries: [
            InventoryMenuEntry(
                item: FormID(0x0100), name: "Lockpick", count: 3, weight: 0, value: 5,
                isEquipped: false, family: .miscellaneous
            )
        ],
        categories: InventoryMenuCategory.engineOrder,
        carriedWeight: 0,
        gold: 42
    )

    func openContainerMenu() {
        containerMenuIsOpen = true
    }

    func closeContainerMenu() {
        containerMenuIsOpen = false
    }

    func sendContainerMenuInput(_ event: MenuInputEvent) {
        switch event {
        case .move(.up): containerMenuModel.moveSelection(by: -1)
        case .move(.down): containerMenuModel.moveSelection(by: 1)
        case .move(.left), .move(.right): switchContainerMenuSide()
        case .button(.accept): activateContainerMenuSelection()
        case .button(.cancel): closeContainerMenu()
        case .pointer: break
        }
    }

    func switchContainerMenuSide() {
        containerMenuModel.switchSide()
    }

    func activateContainerMenuSelection() {
        containerMenuLastAction = containerMenuModel.selectedEntry
            .map { "\(containerMenuModel.transferLabel) \($0.name)." }
    }

    func takeAllFromContainerMenu() {
        containerMenuLastAction = "Took all."
    }

    var containerMenuMerchantOptions: [ContainerMenuMerchantOption] {
        [
            ContainerMenuMerchantOption(
                reference: FormID(0x0300), name: "Test Chest", itemCount: 1, gold: 500
            ),
            ContainerMenuMerchantOption(
                reference: FormID(0x0301), name: "Empty Barrel", itemCount: 0, gold: 0
            )
        ]
    }

    @discardableResult
    func selectContainerMenuMerchant(_ reference: FormID) -> String {
        containerMenuMerchant = reference
        containerMenuLastAction = "Merchant: \(reference)."
        return containerMenuLastAction ?? ""
    }

    @discardableResult
    func selectContainerMenuMerchantFromInteraction() -> String {
        selectContainerMenuMerchant(FormID(0x0301))
    }

    var containerMenuSnapshot: ContainerMenuControlSnapshot {
        let entry = containerMenuModel.selectedEntry
        return ContainerMenuControlSnapshot(
            isOpen: containerMenuIsOpen,
            openMenus: containerMenuIsOpen ? [containerMenuMode == .barter
                ? "BarterMenu" : "ContainerMenu"] : [],
            worldSimPaused: containerMenuIsOpen,
            mode: containerMenuMode,
            side: containerMenuModel.side,
            transferLabel: containerMenuModel.transferLabel,
            containerName: containerMenuModel.containerName,
            entryLines: containerMenuModel.active.entries.map(InventoryMenuSection.line(for:)),
            selectedIndex: containerMenuModel.active.selectedIndex,
            categoryLabels: containerMenuModel.active.categoryLabels,
            selectedCategoryIndex: containerMenuModel.active.selectedCategoryIndex,
            playerGold: containerMenuModel.playerGold,
            containerGold: containerMenuModel.containerGold,
            selectedPrice: entry.flatMap(containerMenuModel.price(for:)),
            canAffordSelection: containerMenuModel.canAffordSelection,
            priceFactor: containerMenuModel.pricing.basePriceFactor,
            pricingSource: containerMenuModel.pricing.source,
            lastActionText: containerMenuLastAction,
            merchantOptions: containerMenuMerchantOptions,
            selectedMerchant: containerMenuMerchant,
            movieEnabled: containerMenuMovieEnabled,
            movieLoaded: false,
            movieError: nil,
            movieDrawStats: SWFDrawStats(),
            movieFaults: 0,
            movieMissingNames: 0,
            movieUnhandledInvokes: 0,
            movieEntryTitles: [],
            movieVendorGold: nil
        )
    }
}
