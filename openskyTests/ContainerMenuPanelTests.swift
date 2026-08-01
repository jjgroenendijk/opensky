// World > Container Menu acceptance-surface coverage (issue #179). Synthetic
// provider state only; the real-install movie bring-up gate is the env-gated
// acceptance test and the `swf container-menu` probe.

import AppKit
@testable import opensky
import Testing

@MainActor
private func tap(_ control: NSControl) {
    control.sendAction(control.action, to: control.target)
}

struct ContainerMenuPanelTests {
    @MainActor
    private func makePanel(_ provider: FakeWorldProviders) -> ContainerMenuPanelViewController {
        let panel = ContainerMenuPanelViewController()
        panel.provider = provider
        panel.loadViewIfNeeded()
        return panel
    }

    /// Accessibility ids are the UI-test contract; pin them literally, and
    /// change these literals in the same commit that renames one.
    @Test @MainActor
    func sectionsExposeStableIdentifiers() {
        let panel = makePanel(FakeWorldProviders())
        #expect(panel.menuSection.sectionIdentifier == "containerMenu")
        #expect(panel.merchantSection.sectionIdentifier == "containerMerchant")
        let controls: [(NSControl, String)] = [
            (panel.merchantSection.merchantControl, "ContainerMerchantSelectControl"),
            (panel.merchantSection.crosshairControl, "ContainerMerchantCrosshairControl"),
            (panel.menuSection.openControl, "ContainerMenuOpenControl"),
            (panel.menuSection.closeControl, "ContainerMenuCloseControl"),
            (panel.menuSection.upControl, "ContainerMenuUpControl"),
            (panel.menuSection.downControl, "ContainerMenuDownControl"),
            (panel.menuSection.switchSideControl, "ContainerMenuSwitchSideControl"),
            (panel.menuSection.transferControl, "ContainerMenuTransferControl"),
            (panel.menuSection.takeAllControl, "ContainerMenuTakeAllControl"),
            (panel.menuSection.barterControl, "ContainerMenuBarterControl"),
            (panel.menuSection.movieControl, "ContainerMenuMovieControl")
        ]
        for (control, identifier) in controls {
            #expect(control.accessibilityIdentifier() == identifier)
        }
    }

    @Test @MainActor
    func buttonsDriveTheProviderAndUnlockOnOpen() {
        let provider = FakeWorldProviders()
        let panel = makePanel(provider)
        let section = panel.menuSection

        section.refreshReadout()
        #expect(section.openControl.isEnabled)
        #expect(!section.transferControl.isEnabled, "actions are locked while closed")

        tap(section.openControl)
        section.refreshReadout()
        #expect(provider.containerMenuIsOpen)
        #expect(section.transferControl.isEnabled)
        #expect(!section.openControl.isEnabled)

        tap(section.downControl)
        tap(section.switchSideControl)
        #expect(provider.containerMenuModel.side == .player)

        tap(section.transferControl)
        #expect(provider.containerMenuLastAction == "Store Lockpick.")

        tap(section.closeControl)
        section.refreshReadout()
        #expect(!provider.containerMenuIsOpen)
    }

    /// Take all is a container action. A merchant does not hand over its stock,
    /// so the control locks in barter mode rather than offering a refusal.
    @Test @MainActor
    func takeAllLocksInBarterMode() {
        let provider = FakeWorldProviders()
        let panel = makePanel(provider)
        let section = panel.menuSection
        tap(section.openControl)
        section.refreshReadout()
        #expect(section.takeAllControl.isEnabled)

        section.barterControl.state = .on
        tap(section.barterControl)
        section.refreshReadout()
        #expect(!section.takeAllControl.isEnabled)
    }

    /// The transfer button says what it will do, because "Transfer" does not
    /// tell a user whether they are about to spend gold.
    @Test @MainActor
    func theTransferButtonNamesTheAction() {
        let provider = FakeWorldProviders()
        provider.containerMenuMode = .barter
        provider.containerMenuModel = ContainerMenuModel(
            mode: .barter,
            container: FakeWorldProviders.merchantList,
            player: FakeWorldProviders.playerList,
            pricing: .vanilla,
            containerName: "Test Chest"
        )
        let panel = makePanel(provider)
        panel.menuSection.refreshReadout()
        #expect(panel.menuSection.transferControl.title == "Buy")
    }

    @Test @MainActor
    func merchantPopupListsResidentContainersAndNominatesOne() {
        let provider = FakeWorldProviders()
        let panel = makePanel(provider)
        let section = panel.merchantSection
        section.refreshReadout()

        #expect(section.merchantControl.numberOfItems == 2)
        #expect(section.merchantControl.itemTitle(at: 1).contains("Empty Barrel"))
        #expect(section.merchantControl.indexOfSelectedItem == 0, "the nominated one is selected")

        section.merchantControl.selectItem(at: 1)
        tap(section.merchantControl)
        #expect(provider.containerMenuMerchant == FormID(0x0301))

        tap(section.crosshairControl)
        #expect(provider.containerMenuLastAction?.contains("Merchant") == true)
    }

    @Test @MainActor
    func readoutReportsBothPursesAndThePrice() {
        let provider = FakeWorldProviders()
        provider.containerMenuIsOpen = true
        provider.containerMenuMode = .barter
        provider.containerMenuModel = ContainerMenuModel(
            mode: .barter,
            container: FakeWorldProviders.merchantList,
            player: FakeWorldProviders.playerList,
            pricing: .vanilla,
            containerName: "Test Chest"
        )
        let readout = ContainerMenuSection.readout(for: provider.containerMenuSnapshot)
        #expect(readout.contains("Container menu: open"))
        #expect(readout.contains("Gold: player 42 · Test Chest 500"))
        // IronSword is worth 25; at the vanilla factor of 3.105 buying costs 78.
        #expect(readout.contains("Buy price: 78 gold (cannot pay)"))
        #expect(readout.contains("Movie: off"))
    }

    @Test @MainActor
    func closedReadoutNamesTheMode() {
        let provider = FakeWorldProviders()
        let readout = ContainerMenuSection.readout(for: provider.containerMenuSnapshot)
        #expect(readout == "Container menu: closed · container mode · world sim running")
    }

    /// An open menu, barter mode and a live movie are all states a user must be
    /// able to see and clear from the sidebar.
    @Test @MainActor
    func overrideAndResetCoverEveryStickyState() {
        let provider = FakeWorldProviders()
        #expect(!ContainerMenuSection.isOverridden(provider: provider))

        provider.openContainerMenu()
        #expect(ContainerMenuSection.isOverridden(provider: provider))
        ContainerMenuSection.resetToDefaults(provider: provider)
        #expect(!ContainerMenuSection.isOverridden(provider: provider))

        provider.containerMenuMode = .barter
        #expect(ContainerMenuSection.isOverridden(provider: provider))
        ContainerMenuSection.resetToDefaults(provider: provider)
        #expect(provider.containerMenuMode == .container)

        provider.containerMenuMovieEnabled = true
        #expect(ContainerMenuSection.isOverridden(provider: provider))
        ContainerMenuSection.resetToDefaults(provider: provider)
        #expect(!provider.containerMenuMovieEnabled)
    }

    @Test @MainActor
    func merchantReadoutSurvivesAnEmptyWorld() {
        let snapshot = ContainerMenuControlSnapshot(
            isOpen: false, openMenus: [], worldSimPaused: false,
            mode: .container, side: .container, transferLabel: "Take",
            containerName: nil, entryLines: [], selectedIndex: 0,
            categoryLabels: [], selectedCategoryIndex: 0,
            playerGold: 0, containerGold: 0, selectedPrice: nil,
            canAffordSelection: true, priceFactor: 3.105, pricingSource: "test",
            lastActionText: nil, merchantOptions: [], selectedMerchant: nil,
            movieEnabled: false, movieLoaded: false, movieError: nil,
            movieDrawStats: SWFDrawStats(), movieFaults: 0, movieMissingNames: 0,
            movieUnhandledInvokes: 0, movieEntryTitles: [], movieVendorGold: nil
        )
        #expect(ContainerMerchantSection.readout(for: snapshot).contains("no resident containers"))
        #expect(ContainerMenuSection.rows(for: snapshot) == "  (this side is empty)")
    }
}
