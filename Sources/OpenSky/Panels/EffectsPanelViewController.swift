// World > Effects: image space, visual effects, and explosions with hazards.
// Each section reaches the session through its own narrow provider protocol.

import AppKit
import OpenSkyCombat
import OpenSkyWorld

final class EffectsPanelViewController: InspectorPanelViewController {
    let imageSpaceSection = ImageSpaceSection()
    let visualEffectSection = VisualEffectSection()
    let explosionSection = ExplosionSection()

    weak var imageSpaceProvider: (any ImageSpaceControlProviding)? {
        didSet { imageSpaceSection.provider = imageSpaceProvider }
    }

    weak var visualEffectProvider: (any VisualEffectControlProviding)? {
        didSet { visualEffectSection.provider = visualEffectProvider }
    }

    weak var explosionProvider: (any ExplosionControlProviding)? {
        didSet { explosionSection.provider = explosionProvider }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [imageSpaceSection, visualEffectSection, explosionSection]
    }
}
