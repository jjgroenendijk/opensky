// World > HUD & Interaction: durable M8.4 acceptance surface. The element
// section owns presentation overrides; the target section reports the exact
// walk-mode selection and the live prompt sent to the vanilla movie.

import AppKit

final class HUDInteractionPanelViewController: InspectorPanelViewController {
    let elementsSection = HUDElementsSection()
    let targetSection = HUDTargetSection()

    weak var provider: (any HUDControlProviding)? {
        didSet {
            elementsSection.provider = provider
            targetSection.provider = provider
            let provider = provider
            refocusAction = { [weak provider] in provider?.refocusGameView() }
        }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [elementsSection, targetSection]
    }
}
