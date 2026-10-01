// World > System Menu. The menu section drives the engine menu stack; the
// settings section shows the data-root and volume rows behind Settings.

import AppKit
import OpenSkyMenus

final class SystemMenuPanelViewController: InspectorPanelViewController {
    let menuSection = SystemMenuSection()
    let settingsSection = SystemMenuSettingsSection()

    weak var provider: (any SystemMenuControlProviding)? {
        didSet {
            menuSection.provider = provider
            settingsSection.provider = provider
            let provider = provider
            refocusAction = { [weak provider] in provider?.refocusGameView() }
        }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [menuSection, settingsSection]
    }
}
