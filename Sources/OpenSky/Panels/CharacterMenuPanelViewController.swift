// World > Character: the title menu and the race menu.

import AppKit
import OpenSkyMenus

final class CharacterMenuPanelViewController: InspectorPanelViewController {
    let titleSection = TitleMenuSection()
    let raceSection = RaceMenuSection()

    weak var provider: (any TitleMenuControlProviding & RaceMenuControlProviding)? {
        didSet {
            titleSection.provider = provider
            raceSection.provider = provider
            let provider = provider
            refocusAction = { [weak provider] in provider?.refocusGameView() }
        }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [titleSection, raceSection]
    }
}
