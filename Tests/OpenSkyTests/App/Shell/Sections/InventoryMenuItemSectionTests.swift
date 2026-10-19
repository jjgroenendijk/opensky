// World > Inventory Menu > Item: the readout lines for the card, the quantity prompt,
// the hotkeys, and the preview.

@testable import OpenSky
import OpenSkyMenus
import OpenSkyRendering
import Testing

struct InventoryMenuItemSectionTests {
    private static func snapshot(_ extras: InventoryMenuExtras) -> InventoryMenuControlSnapshot {
        InventoryMenuControlSnapshot(
            isOpen: true, openMenus: ["InventoryMenu"], worldSimPaused: true,
            categoryLabels: [], selectedCategoryIndex: 0, entryLines: [], selectedIndex: 0,
            carriedWeight: 0, gold: 0, lastActionText: nil, enchantmentLines: [],
            movieEnabled: false, movieLoaded: false, movieError: nil,
            movieDrawStats: SWFDrawStats(), movieFaults: 0, movieMissingNames: 0,
            movieUnhandledInvokes: 0, movieEntryTitles: [], movieCategoryTitles: [],
            extras: extras
        )
    }

    @Test func theReadoutListsTheCardPromptHotkeysAndPreview() {
        let readout = InventoryMenuItemSection.readout(for: Self.snapshot(InventoryMenuExtras(
            itemCard: ["Iron Sword (Weapon)", "Damage 7"],
            quantity: "Drop how many Arrow? 6 of 6",
            hotkeys: ["1: Iron Sword"],
            previewEnabled: true,
            previewLine: "meshes\\weapons\\iron\\longsword.nif, turned 12°"
        )))
        #expect(readout == """
        Iron Sword (Weapon)
        Damage 7
        Drop how many Arrow? 6 of 6
        Hotkeys: 1: Iron Sword
        Preview: meshes\\weapons\\iron\\longsword.nif, turned 12°
        """)
    }

    @Test func anEmptyMenuSaysSoOnEachLine() {
        let readout = InventoryMenuItemSection.readout(for: Self.snapshot(.none))
        #expect(readout == "Card: no row selected\nHotkeys: none\nPreview: off")
    }
}
