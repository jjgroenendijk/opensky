// World > HUD & Interaction: HUD element overrides, the crosshair target and
// its prompt, the item actions on that target, the message tools, and the menu
// screens. The items section takes its own provider because it reads the
// world-item runtime, not the HUD.

import AppKit
import OpenSkyInventory
import OpenSkyMenus

final class HUDInteractionPanelViewController: InspectorPanelViewController {
    let elementsSection = HUDElementsSection()
    let targetSection = HUDTargetSection()
    let itemsSection = ItemsSection()
    let messagesSection = MessagesSection()
    let menuScreensSection = MenuScreensSection()

    weak var provider: (any HUDControlProviding)? {
        didSet {
            elementsSection.provider = provider
            targetSection.provider = provider
        }
    }

    weak var itemProvider: (any ItemControlProviding)? {
        didSet { itemsSection.provider = itemProvider }
    }

    weak var messageProvider: (any MessageControlProviding)? {
        didSet { messagesSection.provider = messageProvider }
    }

    weak var menuScreensProvider: (any MenuScreensControlProviding)? {
        didSet { menuScreensSection.provider = menuScreensProvider }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [elementsSection, targetSection, itemsSection, messagesSection, menuScreensSection]
    }
}
