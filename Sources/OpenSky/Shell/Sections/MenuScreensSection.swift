// HUD & Interaction > Menu screens: open the wait, rest, training, book, help, magic,
// gift, crafting, or map menu, and read what each one did last.

import AppKit
import OpenSkyMenus

final class MenuScreensSection: PanelSectionViewController {
    weak var provider: (any MenuScreensControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let screenControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let openControl = NSButton(title: "Open", target: nil, action: nil)
    private let statsLabel = PanelComponents.statsLabel(identifier: "MenuScreensStatsLabel")

    override var sectionTitle: String {
        "Menu screens"
    }

    override var sectionIdentifier: String {
        "menuScreens"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configurePopUp(
            screenControl, target: self, action: #selector(screenChanged),
            identifier: "MenuScreenSelectControl", width: PanelMetrics.contentWidth
        )
        screenControl.addItems(withTitles: MenuScreenKind.allCases.map(\.rawValue))
        screenControl.toolTip = "The menu to open. Training and gift use the nearest actor."
        openControl.toolTip = "Opens the chosen menu in the game view."
        PanelComponents.configureButton(
            openControl, target: self, action: #selector(openScreen),
            identifier: "MenuScreenOpenControl"
        )
        return [
            PanelComponents.group([screenControl, PanelComponents.buttonRow([openControl])]),
            statsLabel
        ]
    }

    override func syncControls() {
        screenControl.isEnabled = provider != nil
        openControl.isEnabled = provider != nil
    }

    @objc private func screenChanged() {
        finishInteraction()
    }

    @objc private func openScreen() {
        let kinds = MenuScreenKind.allCases
        let index = screenControl.indexOfSelectedItem
        guard kinds.indices.contains(index) else { return }
        provider?.openMenuScreen(kinds[index])
        finishInteraction()
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Menu screens: unavailable"
            return
        }
        statsLabel.stringValue = provider.menuScreenReadouts.map(\.line).joined(separator: "\n")
    }
}
