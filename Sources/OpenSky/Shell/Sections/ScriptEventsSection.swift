// World > Scripts > Events section: the tail of what the VM dispatched, oldest
// first, plus how much is queued and how much the ring dropped. Read-only.

import AppKit
import OpenSkyScripting

final class ScriptEventsSection: PanelSectionViewController {
    weak var provider: (any ScriptControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    private let statsLabel = PanelComponents.statsLabel(identifier: "ScriptEventsStatsLabel")

    override var sectionTitle: String {
        "Events"
    }

    override var sectionIdentifier: String {
        "scriptEvents"
    }

    /// Current readout text; the verification-surface tests read it directly.
    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        statsLabel.toolTip = "Newest last. Dropped events are counted."
        return [
            statsLabel
        ]
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Papyrus: unavailable"
            return
        }
        statsLabel.stringValue = ScriptsReadout.eventsText(for: provider.scriptsSnapshot)
    }
}
