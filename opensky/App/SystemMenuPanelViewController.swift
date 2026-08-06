// World > System Menu: the durable M8.5 verification surface. The menu section
// drives the engine's menu stack; the settings section surfaces the data-root
// and audio-volume placeholders behind the menu's Settings row.

import AppKit

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
