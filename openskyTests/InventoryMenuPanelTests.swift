// World > Inventory Menu acceptance-surface coverage (issue #289). Synthetic
// provider state only; the real-install movie bring-up gate is the env-gated
// acceptance test.

import AppKit
@testable import opensky
import Testing

@MainActor
private func send(_ control: NSControl) {
    control.sendAction(control.action, to: control.target)
}

struct InventoryMenuPanelTests {
    @MainActor
    private func makePanel(
        _ provider: FakeWorldProviders
    ) -> InventoryMenuPanelViewController {
        let panel = InventoryMenuPanelViewController()
        panel.provider = provider
        panel.loadViewIfNeeded()
        return panel
    }

    /// Accessibility ids are the UI-test contract; pin them literally, and
    /// change these literals in the same commit that renames one.
    @Test @MainActor
    func sectionExposesStableIdentifiers() {
        let panel = makePanel(FakeWorldProviders())
        #expect(panel.menuSection.sectionIdentifier == "inventoryMenu")
        let controls: [(NSControl, String)] = [
            (panel.menuSection.openControl, "InventoryMenuOpenControl"),
            (panel.menuSection.closeControl, "InventoryMenuCloseControl"),
            (panel.menuSection.upControl, "InventoryMenuUpControl"),
            (panel.menuSection.downControl, "InventoryMenuDownControl"),
            (
                panel.menuSection.previousCategoryControl,
                "InventoryMenuPreviousCategoryControl"
            ),
            (panel.menuSection.nextCategoryControl, "InventoryMenuNextCategoryControl"),
            (panel.menuSection.equipControl, "InventoryMenuEquipControl"),
            (panel.menuSection.dropControl, "InventoryMenuDropControl"),
            (panel.menuSection.movieControl, "InventoryMenuMovieControl")
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
        #expect(!section.equipControl.isEnabled, "actions are locked while closed")

        send(section.openControl)
        #expect(provider.inventoryMenuIsOpen)
        section.refreshReadout()
        #expect(!section.openControl.isEnabled)
        #expect(section.equipControl.isEnabled)

        send(section.downControl)
        #expect(provider.inventoryMenuSnapshot.selectedIndex == 1)
        send(section.equipControl)
        #expect(provider.inventoryMenuSnapshot.lastActionText == "Equipped Lockpick.")

        send(section.nextCategoryControl)
        #expect(provider.inventoryMenuSnapshot.selectedCategoryIndex == 1)
        #expect(
            provider.inventoryMenuSnapshot.selectedIndex == 0,
            "a new category starts at the top"
        )

        send(section.dropControl)
        #expect(provider.inventoryMenuSnapshot.lastActionText == "Dropped IronSword.")

        send(section.closeControl)
        #expect(!provider.inventoryMenuIsOpen)
    }

    /// The panel buttons and the keyboard must reach the same code, so the
    /// verification surface cannot report a state live input never produces.
    @Test @MainActor
    func panelAndKeyboardShareOnePath() {
        let provider = FakeWorldProviders()
        provider.openInventoryMenu()
        provider.sendInventoryMenuInput(.move(.down))
        let fromKeyboard = provider.inventoryMenuSnapshot.selectedIndex

        let reset = FakeWorldProviders()
        reset.openInventoryMenu()
        let panel = makePanel(reset)
        send(panel.menuSection.downControl)
        #expect(reset.inventoryMenuSnapshot.selectedIndex == fromKeyboard)
    }

    // MARK: - Readout

    @Test @MainActor
    func closedReadoutSaysSo() {
        let provider = FakeWorldProviders()
        #expect(
            InventoryMenuSection.readout(for: provider.inventoryMenuSnapshot)
                == "Inventory menu: closed · world sim running"
        )
    }

    @Test @MainActor
    func openReadoutMarksTheSelectedRowCategoryAndTotals() {
        let provider = FakeWorldProviders()
        provider.openInventoryMenu()
        provider.sendInventoryMenuInput(.move(.down))
        let readout = InventoryMenuSection.readout(for: provider.inventoryMenuSnapshot)
        #expect(readout.contains("Inventory menu: open · world sim paused"))
        #expect(readout.contains("Stack: InventoryMenu"))
        #expect(readout.contains("[All]"))
        #expect(readout.contains("> Lockpick ×3"))
        #expect(readout.contains("  IronSword"))
        #expect(readout.contains("42 gold"))
    }

    @Test @MainActor
    func anEmptyCategorySaysSoRatherThanShowingNothing() {
        let provider = FakeWorldProviders()
        provider.openInventoryMenu()
        let books = try? #require(
            provider.inventoryMenuModel.categoryLabels.firstIndex(of: "Books")
        )
        provider.inventoryMenuModel.selectCategory(books ?? 0)
        let readout = InventoryMenuSection.readout(for: provider.inventoryMenuSnapshot)
        #expect(readout.contains("(no items in this category)"))
    }

    @Test @MainActor
    func movieReadoutDistinguishesOffFailedAndLoaded() {
        let provider = FakeWorldProviders()
        provider.openInventoryMenu()
        #expect(
            InventoryMenuSection.movieReadout(for: provider.inventoryMenuSnapshot)
                == "Movie: off (engine-drawn row list)"
        )
        provider.inventoryMenuMovieEnabled = true
        #expect(
            InventoryMenuSection.movieReadout(for: provider.inventoryMenuSnapshot)
                == "Movie: not loaded"
        )
    }

    /// One row line, in the format the movie bridge and the readout share.
    @Test func rowLineCarriesCountEquippedWeightAndValue() {
        let entry = InventoryMenuEntry(
            item: FormID(0x0300), name: "IronCuirass", count: 2, weight: 30, value: 125,
            isEquipped: true, family: .armor
        )
        #expect(
            InventoryMenuSection.line(for: entry)
                == "IronCuirass ×2 [equipped] · 30.0 wt · 125 gold"
        )
        let single = InventoryMenuEntry(
            item: FormID(0x0100), name: "Lockpick", count: 1, weight: 0, value: 5,
            isEquipped: false, family: .miscellaneous
        )
        #expect(InventoryMenuSection.line(for: single) == "Lockpick · 0.0 wt · 5 gold")
    }

    // MARK: - Overrides

    /// An open menu pauses world sim and the movie takes the SWF layer; both
    /// have to show up in the sidebar as an override the user can clear.
    @Test @MainActor
    func openMenuAndMovieBothCountAsOverridden() {
        let provider = FakeWorldProviders()
        #expect(!InventoryMenuSection.isOverridden(provider: provider))
        provider.openInventoryMenu()
        #expect(InventoryMenuSection.isOverridden(provider: provider))
        InventoryMenuSection.resetToDefaults(provider: provider)
        #expect(!provider.inventoryMenuIsOpen)

        provider.inventoryMenuMovieEnabled = true
        #expect(InventoryMenuSection.isOverridden(provider: provider))
        InventoryMenuSection.resetToDefaults(provider: provider)
        #expect(!provider.inventoryMenuMovieEnabled)
    }
}
