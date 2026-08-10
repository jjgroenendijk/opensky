// World > HUD & Interaction: durable M8.4 acceptance surface. The element
// section owns presentation overrides; the target section reports the exact
// walk-mode selection and the live prompt sent to the vanilla movie; the items
// section (M12.1.3) acts on that selection — take, search, drop; the dialogue
// section (M17.3) acts on it when the selection is an actor; the dialogue
// camera section (M17.4) shows what a conversation did to the view and to the
// actor it is with.
//
// The items and dialogue sections take providers of their own because they read
// the world-item runtime and the dialogue layer rather than the HUD. All four
// are the same object in the app; typing them apart keeps each section's
// dependency honest.

import AppKit

final class HUDInteractionPanelViewController: InspectorPanelViewController {
    let elementsSection = HUDElementsSection()
    let targetSection = HUDTargetSection()
    let itemsSection = ItemsSection()
    let dialogueSection = DialogueSection()
    let dialogueCameraSection = DialogueCameraSection()

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

    weak var dialogueCameraProvider: (any DialogueCameraControlProviding)? {
        didSet { dialogueCameraSection.provider = dialogueCameraProvider }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [elementsSection, targetSection, itemsSection, dialogueSection, dialogueCameraSection]
    }
}
