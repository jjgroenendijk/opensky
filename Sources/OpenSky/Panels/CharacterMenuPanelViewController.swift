// World > Character: the title menu, the race menu, and the skills menu.

import AppKit
import OpenSkyMenus

final class CharacterMenuPanelViewController: InspectorPanelViewController {
    let titleSection = TitleMenuSection()
    let raceSection = RaceMenuSection()
    let skillsSection = SkillsMenuSection()

    weak var titleProvider: (any TitleMenuControlProviding)? {
        didSet { titleSection.provider = titleProvider }
    }

    weak var raceProvider: (any RaceMenuControlProviding)? {
        didSet { raceSection.provider = raceProvider }
    }

    weak var skillsProvider: (any SkillsMenuControlProviding)? {
        didSet { skillsSection.provider = skillsProvider }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [titleSection, raceSection, skillsSection]
    }
}
