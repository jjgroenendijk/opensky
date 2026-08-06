// World > Inventory Menu: the M12.2 verification surface. One section, which
// drives the engine's menu stack on the player's inventory and reports both the
// engine-side row list and what the vanilla movie built from it.

import AppKit

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
