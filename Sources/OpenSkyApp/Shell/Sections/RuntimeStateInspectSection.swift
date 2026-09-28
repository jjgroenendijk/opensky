// World > Runtime State > Inspect section (M10.1.5): the read-only view of the
// world-state store — how many references the resident cells hold, how many of
// them deviate from plugin data, and the tail of the mutation journal.
//
// Purely a readout, so it is never overridden and its reset is a no-op: nothing
// here is a setting the user can leave in a non-default position.

import AppKit

final class RuntimeStateInspectSection: PanelSectionViewController {
    weak var provider: (any RuntimeStateControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    private let statsLabel = PanelComponents.statsLabel(identifier: "RuntimeStateStatsLabel")
    private let journalLabel = PanelComponents.statsLabel(
        identifier: "RuntimeStateJournalStatsLabel"
    )

    override var sectionTitle: String {
        "Inspect"
    }

    override var sectionIdentifier: String {
        "runtimeStateInspect"
    }

    /// Current readout texts; the verification-surface tests read them directly.
    var readout: String {
        statsLabel.stringValue
    }

    var journalReadout: String {
        journalLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        [
            PanelComponents.note(
                "Counts come from the live world-state store. A reference is dirty when it "
                    + "carries a runtime delta the loaded plugins do not describe."
            ),
            statsLabel,
            PanelComponents.caption("Journal (most recent last)"),
            journalLabel
        ]
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Runtime state: unavailable"
            journalLabel.stringValue = ""
            return
        }
        let snapshot = provider.runtimeStateSnapshot
        statsLabel.stringValue = [
            "Resident references: \(snapshot.residentReferenceCount)",
            "Dirty references: \(snapshot.dirtyReferenceCount)",
            "Next sequence: \(snapshot.nextJournalSequence)"
                + "  Dropped: \(snapshot.droppedJournalEntryCount)"
        ].joined(separator: "\n")
        journalLabel.stringValue = snapshot.journalTail.isEmpty
            ? "No mutations recorded."
            : snapshot.journalTail.joined(separator: "\n")
    }
}
