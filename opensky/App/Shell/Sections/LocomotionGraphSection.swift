// World > Player & Locomotion > Behavior Graph section (issue #191): the live
// graph, read-only.
//
// The active state path, the variables the bridge writes with the values the
// graph holds, the events raised and the events that came back, and the
// evaluator's own coverage tally. Read-only on purpose: driving the graph is
// the Dev Controls section's job, and a readout that could also mutate would
// make "what the graph did" and "what the panel did to it" hard to separate.

import AppKit

final class LocomotionGraphSection: PanelSectionViewController {
    weak var provider: (any PlayerLocomotionControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            refreshReadout()
        }
    }

    private let statsLabel = PanelComponents.statsLabel(
        identifier: "LocomotionGraphStatsLabel"
    )

    override var sectionTitle: String {
        "Behavior Graph"
    }

    override var sectionIdentifier: String {
        "locomotionGraph"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        [
            PanelComponents.note(
                "The player's own graph from the install, stepped on the simulation clock. "
                    + "A variable listed as not declared is a name OpenSky writes that this "
                    + "graph spells differently, which is a binding failure rather than a "
                    + "silent no-op."
            ),
            statsLabel
        ]
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Behavior graph: unavailable"
            return
        }
        statsLabel.stringValue = PlayerLocomotionReadout.graphText(
            for: provider.playerLocomotionSnapshot
        )
    }
}
