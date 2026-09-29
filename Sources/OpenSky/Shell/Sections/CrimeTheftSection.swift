// World > Crime & Factions > Theft (issue #507): whether taking what the
// crosshair is on would be theft, whose it is, and the stolen copies the player
// already carries.
//
// Read-only, as `ItemOwnershipSection` is: ownership is a fact about a placed
// reference, not a setting. That section shows the raw `XOWN`/`XRNK` fields;
// this one shows the verdict the crime runtime reaches from them, the cell's
// owner and the player's memberships (issue #504), which is the question a
// thief is actually asking.

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
