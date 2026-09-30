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
        [
            PanelComponents.note(
                "Events the VM dispatched, most recent last. Pending events are queued for "
                    + "the next tick; dropped events left the ring to make room for newer "
                    + "ones and are counted rather than hidden."
            ),
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
