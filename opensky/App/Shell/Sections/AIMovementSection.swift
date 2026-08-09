// World > AI & Navigation > Movement section (issue #423, roadmap item 16.4;
// shipped by the M16 gate, issue #203): the move-to-point dev control and the
// mover readout the path follower publishes.
//
// Two buttons and no field. "Where" is the crosshair, because a point in a city
// is not a number a person knows and the pick already reaches 8,192 units;
// typing three floats would be a worse version of looking at the spot. Stop is
// its counterpart, and both are one-shots, so both are buttons.
//
// Not overridden. Where an actor has walked to is world state a user asked for,
// and a "Reset all" that teleported every NPC back to its authored placement
// would undo the thing the destination exists to demonstrate. `World > Runtime
// State > Reset` already owns dropping reference transforms.

import AppKit

final class AIMovementSection: PanelSectionViewController {
    weak var provider: (any AINavigationControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let moveControl = NSButton(title: "Move to crosshair", target: nil, action: nil)
    let stopControl = NSButton(title: "Stop", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(identifier: "AIMovementStatsLabel")

    override var sectionTitle: String {
        "Movement"
    }

    override var sectionIdentifier: String {
        "aiMovement"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureButton(
            moveControl, target: self, action: #selector(moveToCrosshair),
            identifier: "AIMoveToCrosshairControl"
        )
        PanelComponents.configureButton(
            stopControl, target: self, action: #selector(stop),
            identifier: "AIMoveStopControl"
        )
        return [
            PanelComponents.note(
                "Move paths the selected actor to whatever the crosshair is pointing at, "
                    + "through the navmesh: the point is projected onto the nearest walkable "
                    + "triangle, so aiming at a wall a little above the floor still works. "
                    + "The actor walks or runs by distance, opens the doors on its route, "
                    + "and repaths when a cell it was crossing unloads. Stop leaves it "
                    + "standing where it is. Both act on the actor selected above."
            ),
            PanelComponents.buttonRow([moveControl, stopControl]),
            statsLabel
        ]
    }

    override func syncControls() {
        let available = provider != nil
        moveControl.isEnabled = available
        stopControl.isEnabled = available
    }

    override func refreshReadout() {
        guard let snapshot = provider?.aiNavigationSnapshot else {
            statsLabel.stringValue = "Movement: unavailable"
            return
        }
        statsLabel.stringValue = AINavigationReadout.movementText(for: snapshot)
    }

    // MARK: - Actions

    @objc private func moveToCrosshair() {
        provider?.moveSelectedAIActorToCrosshair()
        finishInteraction()
    }

    @objc private func stop() {
        provider?.stopSelectedAIActor()
        finishInteraction()
    }
}
