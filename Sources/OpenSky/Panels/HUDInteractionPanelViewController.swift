// World > HUD & Interaction: HUD element overrides, the crosshair target and
// its prompt, and the item actions on that target. The items section takes its
// own provider because it reads the world-item runtime, not the HUD.

import AppKit
import OpenSkyInventory
import OpenSkyMenus

final class HUDInteractionPanelViewController: InspectorPanelViewController {
    let elementsSection = HUDElementsSection()
    let targetSection = HUDTargetSection()
    let itemsSection = ItemsSection()

    weak var provider: (any HUDControlProviding)? {
        didSet {
            elementsSection.provider = provider
            targetSection.provider = provider
            let provider = provider
            refocusAction = { [weak provider] in provider?.refocusGameView() }
        }
    }

    weak var itemProvider: (any ItemControlProviding)? {
        didSet { itemsSection.provider = itemProvider }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [elementsSection, targetSection, itemsSection]
    }
}
