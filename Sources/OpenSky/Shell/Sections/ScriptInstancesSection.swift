// World > Scripts > Instances section: how many script instances the world
// runtime holds, and which scripts sit on the reference under the crosshair.
// Read-only.

import AppKit
import OpenSkyScripting

final class ScriptInstancesSection: PanelSectionViewController {
    weak var provider: (any ScriptControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    private let statsLabel = PanelComponents.statsLabel(identifier: "ScriptInstancesStatsLabel")

    override var sectionTitle: String {
        "Instances"
    }

    override var sectionIdentifier: String {
        "scriptInstances"
    }

    /// Current readout text; the verification-surface tests read it directly.
    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        statsLabel.toolTip = "The target is the crosshair reference."
        return [
            statsLabel
        ]
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Papyrus: unavailable"
            return
        }
        statsLabel.stringValue = ScriptsReadout.instancesText(for: provider.scriptsSnapshot)
    }
}
