// The inventory menu's sidebar seam, forwarded to `InventoryMenuController`.

import OpenSkyMenus

extension GameViewController: InventoryMenuControlProviding {
    var inventoryMenuIsOpen: Bool {
        inventoryMenu.isOpen
    }

    var inventoryMenuMovieEnabled: Bool {
        get { inventoryMenu.movieEnabled }
        set { inventoryMenu.setMovieEnabled(newValue) }
    }

    var inventoryMenuSnapshot: InventoryMenuControlSnapshot {
        inventoryMenu.snapshot
    }

    func openInventoryMenu() {
        inventoryMenu.open()
    }

    func closeInventoryMenu() {
        inventoryMenu.close()
    }

    func sendInventoryMenuInput(_ event: MenuInputEvent) {
        inventoryMenu.route(event)
    }

    func activateInventoryMenuSelection() {
        inventoryMenu.activateSelection()
    }

    func dropInventoryMenuSelection() {
        inventoryMenu.dropSelection()
    }

    func consumeInventoryMenuSelection() {
        inventoryMenu.consumeSelection()
    }

    func dropInventoryMenuSelection(count: Int32) {
        inventoryMenu.dropSelection(count: count)
    }

    func toggleInventoryMenuFavourite() {
        inventoryMenu.toggleFavouriteSelection()
    }

    func bindInventoryMenuHotkey(_ slot: Int) {
        inventoryMenu.bindHotkey(slot)
    }

    func useInventoryHotkey(_ slot: Int) {
        inventoryMenu.useHotkey(slot)
    }

    var inventoryMenuPreviewEnabled: Bool {
        get { inventoryMenu.previewEnabled }
        set { inventoryMenu.setPreviewEnabled(newValue) }
    }
}
