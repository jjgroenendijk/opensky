// World > Inventory & Equipment > Crafting and Harvest with the provider fake:
// pinned ids, the station dev control, the recipe verdicts, and a forced harvest.

import AppKit
@testable import OpenSky
@testable import OpenSkyInventory
import Testing

@MainActor
struct CraftingPanelTests {
    private func tap(_ control: NSControl) {
        control.sendAction(control.action, to: control.target)
    }

    private func panel(_ provider: FakeWorldProviders) -> InventoryEquipmentPanelViewController {
        let panel = InventoryEquipmentPanelViewController()
        panel.provider = provider
        panel.craftingProvider = provider
        panel.loadViewIfNeeded()
        return panel
    }

    @Test func accessibilityIdentifiersArePinned() {
        let panel = panel(FakeWorldProviders())
        #expect(panel.craftingSection.sectionIdentifier == "crafting")
        #expect(panel.harvestSection.sectionIdentifier == "harvest")
        let controls: [(NSView, String)] = [
            (panel.craftingSection.stationControl, "CraftingStationControl"),
            (panel.craftingSection.openControl, "CraftingOpenControl"),
            (panel.craftingSection.closeControl, "CraftingCloseControl"),
            (panel.craftingSection.recipeControl, "CraftingRecipeControl"),
            (panel.craftingSection.craftControl, "CraftingCraftControl"),
            (panel.harvestSection.harvestControl, "HarvestForceControl"),
            (panel.harvestSection.resetControl, "HarvestResetControl")
        ]
        for (control, identifier) in controls {
            #expect(control.accessibilityIdentifier() == identifier)
        }
    }

    @Test func openingAStationListsRecipeVerdicts() {
        let provider = FakeWorldProviders()
        let panel = panel(provider)
        let section = panel.craftingSection
        #expect(section.readout.contains("Station: none"))
        #expect(section.stationControl.itemTitles == [FakeWorldProviders.forgeEditorID])
        tap(section.openControl)
        section.refreshReadout()
        #expect(section.readout.contains("Station: CraftingSmithingForge"))
        #expect(section.readout.contains("Iron Sword: missing Iron Ingot 0 of 1"))
        #expect(section.readout.contains("Iron Dagger: ready"))
        #expect(section.recipeControl.itemTitles == ["Iron Sword", "Iron Dagger"])
    }

    @Test func craftDrivesTheSelectedRecipe() {
        let provider = FakeWorldProviders()
        let section = panel(provider).craftingSection
        tap(section.openControl)
        section.refreshReadout()
        section.recipeControl.selectItem(at: 1)
        tap(section.craftControl)
        section.refreshReadout()
        #expect(provider.crafting.crafted == 1)
        #expect(section.readout.contains("Last: Crafted 1 × Iron Dagger."))
    }

    @Test func harvestAndResetDriveTheProvider() {
        let provider = FakeWorldProviders()
        let section = panel(provider).harvestSection
        #expect(section.readout.contains("Harvested: no"))
        tap(section.harvestControl)
        section.refreshReadout()
        #expect(section.readout.contains("Harvested: yes"))
        #expect(section.readout.contains("Grows back: in 10.0 game days"))
        tap(section.resetControl)
        section.refreshReadout()
        #expect(section.readout.contains("Harvested: no"))
    }
}
