// World > Scripts > Native coverage section: which Papyrus natives the session
// called, and which missing ones cost the most. Coverage is observed, not
// registered. Read-only.

import AppKit
import OpenSkyScripting

final class ScriptNativeTallySection: PanelSectionViewController {
    weak var provider: (any ScriptControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    private let statsLabel = PanelComponents.statsLabel(
        identifier: "ScriptNativeTallyStatsLabel"
    )

    override var sectionTitle: String {
        "Native coverage"
    }

    override var sectionIdentifier: String {
        "scriptNativeTally"
    }

    /// Current readout text; the verification-surface tests read it directly.
    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        statsLabel.toolTip = "Engine functions that scripts called but OpenSky does not have yet."
        return [
            statsLabel
        ]
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Papyrus: unavailable"
            return
        }
        statsLabel.stringValue = ScriptsReadout.nativeTallyText(for: provider.scriptsSnapshot)
    }
}
