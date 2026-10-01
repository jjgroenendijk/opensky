// World > Crime & Factions > Theft: whether taking the crosshair target is
// theft, whose it is, and the stolen items the player carries. Read-only,
// because ownership is a fact about a placed reference.

import AppKit
import OpenSkyCrime

final class CrimeTheftSection: CrimeFactionPanelSection {
    private let statsLabel = PanelComponents.statsLabel(identifier: "CrimeTheftStatsLabel")

    override var sectionTitle: String {
        "Theft"
    }

    override var sectionIdentifier: String {
        "crimeTheft"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        [
            PanelComponents.note(
                "The ownership verdict for the reference under the walk-mode crosshair: "
                    + "its own XOWN, else its cell's, judged against the player's "
                    + "memberships and ranks — the same verdict a take is charged by. "
                    + "Below it, every stolen stack the player carries; merchants other "
                    + "than fences refuse these."
            ),
            statsLabel
        ]
    }

    override func refreshReadout() {
        guard let snapshot = currentSnapshot else {
            statsLabel.stringValue = "Theft: unavailable"
            return
        }
        statsLabel.stringValue = CrimeFactionReadout.theftText(for: snapshot)
    }
}
