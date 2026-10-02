// World > AI & Navigation > Movement section: move-to-point and stop buttons,
// and the path follower's readout. The target is the crosshair, not typed
// coordinates. Not overridden: where an actor walked is world state; World >
// Runtime State > Reset drops reference transforms.

import AppKit
import OpenSkyWorld

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

    override func makeContentViews() -> [NSView] {
        moveControl.toolTip = "Walks the selected actor to the point under the crosshair."
        PanelComponents.configureButton(
            moveControl, target: self, action: #selector(moveToCrosshair),
            identifier: "AIMoveToCrosshairControl"
        )
        PanelComponents.configureButton(
            stopControl, target: self, action: #selector(stop),
            identifier: "AIMoveStopControl"
        )
        return [
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
