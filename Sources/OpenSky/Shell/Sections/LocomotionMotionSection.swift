// World > Player & Locomotion > Root Motion section: which source moved the
// capsule and how far each carried it. Each fixed step has one horizontal
// source: the graph's root travel, or else the gait speed. Vanilla clips
// animate in place, so the root-motion total stays zero on vanilla data.

import AppKit
import OpenSkyWorld

final class LocomotionMotionSection: PanelSectionViewController {
    weak var provider: (any PlayerLocomotionControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let clearTraceControl = NSButton(title: "Clear trace", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(
        identifier: "LocomotionMotionStatsLabel"
    )

    override var sectionTitle: String {
        "Root Motion"
    }

    override var sectionIdentifier: String {
        "locomotionMotion"
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureButton(
            clearTraceControl, target: self, action: #selector(clearTrace),
            identifier: "LocomotionTraceClearControl"
        )
        return [
            PanelComponents.note(
                "One step has one motion source. Vanilla locomotion clips animate in place, "
                    + "so the root-motion total stays at zero and the configured-speed total "
                    + "grows; a clip set carrying extracted motion reverses that."
            ),
            PanelComponents.buttonRow([clearTraceControl]),
            statsLabel
        ]
    }

    override func syncControls() {
        clearTraceControl.isEnabled = provider != nil
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Root motion: unavailable"
            return
        }
        statsLabel.stringValue = PlayerLocomotionReadout.motionText(
            for: provider.playerLocomotionSnapshot
        )
    }

    @objc private func clearTrace() {
        provider?.clearLocomotionTrace()
        finishInteraction()
    }
}
