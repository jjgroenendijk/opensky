// World > Player & Locomotion > Actor State section: the actor-state variables the
// engine writes into the graph and the ones the graph publishes back, read-only
// (docs/engine/actor-state-graph.md).

import AppKit
import OpenSkyPlayer

final class LocomotionActorStateSection: PanelSectionViewController {
    weak var provider: (any PlayerLocomotionControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            refreshReadout()
        }
    }

    private let statsLabel = PanelComponents.statsLabel(
        identifier: "LocomotionActorStateStatsLabel"
    )

    override var sectionTitle: String {
        "Actor State"
    }

    override var sectionIdentifier: String {
        "locomotionActorState"
    }

    override func makeContentViews() -> [NSView] {
        statsLabel.toolTip = "What the game tells the animation graph, and what it reports back."
        return [statsLabel]
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Actor state: unavailable"
            return
        }
        statsLabel.stringValue = ActorStateGraphReadout.text(
            for: provider.playerLocomotionSnapshot.actorState
        )
    }
}
