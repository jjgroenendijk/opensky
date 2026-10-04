// World > System Menu. The menu section drives the engine menu stack, the page
// section the open sub-page, and the settings section the data root and volume.

import AppKit
import OpenSkyMenus

final class SystemMenuPanelViewController: InspectorPanelViewController {
    let menuSection = SystemMenuSection()
    let pageSection = SystemMenuPageSection()
    let settingsSection = SystemMenuSettingsSection()

    weak var provider: (any SystemMenuControlProviding)? {
        didSet {
            menuSection.provider = provider
            pageSection.provider = provider
            settingsSection.provider = provider
            let provider = provider
            refocusAction = { [weak provider] in provider?.refocusGameView() }
        }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [menuSection, pageSection, settingsSection]
    }
}
