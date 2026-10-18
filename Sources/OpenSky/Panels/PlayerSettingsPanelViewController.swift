// World > Settings: every player setting beside its default, the key bindings,
// the difficulty with its resolved multipliers, and the Survival Mode answer.

import AppKit
import OpenSkyMenus

final class PlayerSettingsPanelViewController: InspectorPanelViewController {
    let settingsSection = PlayerSettingsTableSection()
    let bindingsSection = KeyBindingsSection()
    let difficultySection = DifficultySection()
    let survivalModeSection = SurvivalModeSection()

    weak var provider: (any PlayerSettingsControlProviding)? {
        didSet {
            settingsSection.provider = provider
            bindingsSection.provider = provider
            difficultySection.provider = provider
        }
    }

    weak var survivalModeProvider: (any SurvivalModeControlProviding)? {
        didSet { survivalModeSection.provider = survivalModeProvider }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [settingsSection, bindingsSection, difficultySection, survivalModeSection]
    }
}
