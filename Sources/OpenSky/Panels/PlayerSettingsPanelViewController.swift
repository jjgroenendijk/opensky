// World > Settings: every player setting beside its default, the key bindings,
// and the difficulty with its resolved multipliers.

import AppKit
import OpenSkyMenus

final class PlayerSettingsPanelViewController: InspectorPanelViewController {
    let settingsSection = PlayerSettingsTableSection()
    let bindingsSection = KeyBindingsSection()
    let difficultySection = DifficultySection()

    weak var provider: (any PlayerSettingsControlProviding)? {
        didSet {
            settingsSection.provider = provider
            bindingsSection.provider = provider
            difficultySection.provider = provider
            let provider = provider
            refocusAction = { [weak provider] in provider?.refocusGameView() }
        }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [settingsSection, bindingsSection, difficultySection]
    }
}
