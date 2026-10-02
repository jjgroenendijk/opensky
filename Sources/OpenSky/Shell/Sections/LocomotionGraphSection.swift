// World > Player & Locomotion > Behavior Graph section: the live graph,
// read-only, so "what the graph did" stays apart from "what the panel did".
// Dev Controls drives the graph.

import AppKit
import OpenSkyWorld

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

    override func makeContentViews() -> [NSView] {
        statsLabel.toolTip =
            "A variable marked not declared is a bug: the name does not match the game's."
        return [
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
