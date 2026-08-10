// World > HUD & Interaction: durable M8.4 acceptance surface. The element
// section owns presentation overrides; the target section reports the exact
// walk-mode selection and the live prompt sent to the vanilla movie; the items
// section (M12.1.3) acts on that selection — take, search, drop; the dialogue
// section (M17.3) acts on it when the selection is an actor.
//
// The items and dialogue sections take providers of their own because they read
// the world-item runtime and the dialogue layer rather than the HUD. All three
// are the same object in the app; typing them apart keeps each section's
// dependency honest.

import AppKit

final class HUDInteractionPanelViewController: InspectorPanelViewController {
    let elementsSection = HUDElementsSection()
    let targetSection = HUDTargetSection()
    let itemsSection = ItemsSection()
    let dialogueSection = DialogueSection()

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

    weak var dialogueProvider: (any DialogueControlProviding)? {
        didSet { dialogueSection.provider = dialogueProvider }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [elementsSection, targetSection, itemsSection, dialogueSection]
    }
}
