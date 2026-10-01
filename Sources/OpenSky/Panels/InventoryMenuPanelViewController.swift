// World > Inventory Menu. Drives the engine menu stack on the player's
// inventory and reports the engine rows and what the vanilla movie built.

import AppKit
import OpenSkyMenus

final class InventoryMenuPanelViewController: InspectorPanelViewController {
    let menuSection = InventoryMenuSection()

    weak var provider: (any InventoryMenuControlProviding)? {
        didSet {
            menuSection.provider = provider
        }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [menuSection]
    }
}
