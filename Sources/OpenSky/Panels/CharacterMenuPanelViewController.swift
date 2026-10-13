// World > Character: the title menu, the race menu, and the skills menu.

import AppKit
import OpenSkyMenus

final class CharacterMenuPanelViewController: InspectorPanelViewController {
    let titleSection = TitleMenuSection()
    let raceSection = RaceMenuSection()
    let skillsSection = SkillsMenuSection()

    weak var provider: (
        any TitleMenuControlProviding & RaceMenuControlProviding & SkillsMenuControlProviding
    )? {
        didSet {
            titleSection.provider = provider
            raceSection.provider = provider
            skillsSection.provider = provider
            let provider = provider
            refocusAction = { [weak provider] in provider?.refocusGameView() }
        }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [titleSection, raceSection, skillsSection]
    }
}
