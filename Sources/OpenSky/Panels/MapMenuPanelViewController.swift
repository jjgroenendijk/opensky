// World > Map: the world map, the local map, markers, and fast travel.

import AppKit
import OpenSkyMenus

final class MapMenuPanelViewController: InspectorPanelViewController {
    let mapSection = MapMenuSection()

    weak var provider: (any MapMenuControlProviding)? {
        didSet {
            mapSection.provider = provider
            let provider = provider
            refocusAction = { [weak provider] in provider?.refocusGameView() }
        }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [mapSection]
    }
}
