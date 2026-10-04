// World > Loading Screens: force any loading screen, turn them off for door
// transitions, and see which screens pass where the player stands.

import AppKit
import OpenSkyWorld

final class LoadingScreenSection: PanelSectionViewController {
    weak var provider: (any LoadingScreenControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            refreshReadout()
        }
    }

    let screenControl = NSComboBox()
    let forceControl = NSButton(title: "Show", target: nil, action: nil)
    let releaseControl = NSButton(title: "Release", target: nil, action: nil)
    let enabledControl = NSButton(checkboxWithTitle: "Loading screens", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(identifier: "LoadingScreenStatsLabel")
    private var screenNames: [String] = []

    override var sectionTitle: String {
        "Loading Screens"
    }

    override var sectionIdentifier: String {
        "loadingScreens"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        screenControl.toolTip = "The loading screen to hold on screen."
        PanelComponents.configureComboBox(
            screenControl, target: self, action: #selector(force),
            identifier: "LoadingScreenControl", width: 170
        )
        forceControl.toolTip = "Holds the chosen screen until Release."
        PanelComponents.configureButton(
            forceControl, target: self, action: #selector(force),
            identifier: "LoadingScreenForceControl"
        )
        PanelComponents.configureButton(
            releaseControl, target: self, action: #selector(releaseForcedScreen),
            identifier: "LoadingScreenReleaseControl"
        )
        enabledControl.toolTip = "Door transitions cover the view while the next cell loads."
        PanelComponents.configureCheckbox(
            enabledControl, target: self, action: #selector(toggleEnabled),
            identifier: "LoadingScreenEnabledControl"
        )
        return [
            PanelComponents.group([
                PanelComponents.labeledFieldRow(
                    caption: "Screen",
                    captionWidth: 60,
                    field: screenControl
                ),
                PanelComponents.buttonRow([forceControl, releaseControl]),
                enabledControl
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        sync(provider?.loadingScreenSnapshot ?? LoadingScreenSnapshot())
    }

    private func sync(_ snapshot: LoadingScreenSnapshot) {
        if snapshot.screenNames != screenNames {
            screenNames = snapshot.screenNames
            screenControl.removeAllItems()
            screenControl.addItems(withObjectValues: screenNames)
        }
        for control in [screenControl, forceControl, enabledControl] {
            control.isEnabled = snapshot.isAvailable
        }
        releaseControl.isEnabled = snapshot.isForced
        enabledControl.state = snapshot.isEnabled ? .on : .off
    }

    override func refreshReadout() {
        let snapshot = provider?.loadingScreenSnapshot ?? LoadingScreenSnapshot()
        sync(snapshot)
        statsLabel.stringValue = LoadingScreenReadout.text(for: snapshot)
    }

    @objc private func force() {
        let name = screenControl.stringValue
        guard !name.isEmpty else { return }
        provider?.forceLoadingScreen(editorID: name)
        finishInteraction()
    }

    @objc private func releaseForcedScreen() {
        provider?.releaseLoadingScreen()
        finishInteraction()
    }

    @objc private func toggleEnabled() {
        provider?.loadingScreensEnabled = enabledControl.state == .on
        finishInteraction()
    }
}
