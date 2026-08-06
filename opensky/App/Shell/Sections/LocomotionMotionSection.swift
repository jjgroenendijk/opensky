// World > Player & Locomotion > Root Motion section (issue #191): which source
// moved the capsule, and how far each one has carried it.
//
// The movement-authority rule says horizontal motion has exactly one source per
// fixed step — the graph's own root travel when the data carries any, the
// resolved gait speed otherwise. This section is where that rule is visible:
// two running totals that cannot both grow on one step, and a trace of the
// steps at which the answer changed. On vanilla data the root-motion total
// stays at zero, because Skyrim's locomotion clips animate in place; a data set
// that does carry extracted motion shows up here rather than looking identical.

import AppKit

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

    var readout: String {
        statsLabel.stringValue
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
