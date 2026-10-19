// The inventory menu's favourites, hotkeys, counted drop, and preview switch on the
// world-provider fake. State lives in `FakeInventoryEquipmentState` for the lint caps.

import OpenSkyMenus

extension FakeWorldProviders {
    func dropInventoryMenuSelection(count: Int32) {
        inventoryMenuLastAction = inventoryMenuModel.selectedEntry
            .map { "Dropped \(count) \($0.name)." }
    }

    func toggleInventoryMenuFavourite() {
        inventoryMenuLastAction = inventoryMenuModel.selectedEntry
            .map { "\($0.name) is a favourite." }
    }

    func bindInventoryMenuHotkey(_ slot: Int) {
        inventoryMenuLastAction = inventoryMenuModel.selectedEntry
            .map { "Hotkey \(slot) uses \($0.name)." }
    }

    func useInventoryHotkey(_ slot: Int) {
        inventoryMenuLastAction = "Hotkey \(slot) has no favourite."
    }

    var inventoryMenuPreviewEnabled: Bool {
        get { inventoryEquipment.menuPreviewEnabled }
        set { inventoryEquipment.menuPreviewEnabled = newValue }
    }
}
