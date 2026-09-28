// World > Scripts > Events section (issue #278): the tail of what the VM
// actually dispatched, plus how much is still queued and how much the ring
// pushed out.
//
// The tail is presented the way the Runtime State journal tail is — oldest
// first, most recent last — because both answer the same question: what did the
// engine just do, in order. Read-only, so it is never overridden.

import AppKit

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
