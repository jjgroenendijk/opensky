// World > HUD & Interaction: durable M8.4 acceptance surface. The element
// section owns presentation overrides; the target section reports the exact
// walk-mode selection and the live prompt sent to the vanilla movie; the items
// section (M12.1.3) acts on that selection — take, search, drop.
//
// The items section takes a second provider because it reads the world-item
// runtime rather than the HUD. Both are the same object in the app; typing them
// apart keeps each section's dependency honest.

import AppKit

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
