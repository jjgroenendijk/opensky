// World > Player & Locomotion > Bindings section (issue #191): every gameplay
// key this milestone added, listed with its live state and reachable from a
// control.
//
// This section exists because of the app-ui rule that no gameplay behavior may
// be reachable only by an unadvertised keystroke. Sneak is a toggle and is
// offered as one; jump is momentary and is offered as a button that requests
// exactly one jump, the same latch the space bar sets. Sprint and run are held
// modifiers with nothing to latch — a button would assert them for a single
// frame and read as broken — so they are listed and reported live instead:
// hold the key and the row turns active.
//
// Not overridden. A sneaking player is world state, not a panel setting, and a
// "Reset all" that stood the player up would undo something the user did on
// purpose.

import AppKit

final class LocomotionBindingsSection: PanelSectionViewController {
    weak var provider: (any PlayerLocomotionControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let sneakControl = NSButton(checkboxWithTitle: "Sneak", target: nil, action: nil)
    let jumpControl = NSButton(title: "Jump", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(
        identifier: "LocomotionBindingsStatsLabel"
    )

    override var sectionTitle: String {
        "Bindings"
    }

    override var sectionIdentifier: String {
        "locomotionBindings"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureCheckbox(
            sneakControl, target: self, action: #selector(sneakChanged),
            identifier: "LocomotionSneakControl"
        )
        PanelComponents.configureButton(
            jumpControl, target: self, action: #selector(jump),
            identifier: "LocomotionJumpControl"
        )
        return [
            PanelComponents.note(
                "Run and sprint are held modifiers with no state to set from here; hold the "
                    + "key and watch the row below turn active. Jump requests exactly one "
                    + "jump, which a step on solid ground consumes."
            ),
            PanelComponents.group([sneakControl, PanelComponents.buttonRow([jumpControl])]),
            statsLabel
        ]
    }

    override func syncControls() {
        sneakControl.isEnabled = provider != nil
        jumpControl.isEnabled = provider != nil
        guard let provider else { return }
        sneakControl.state = provider.isSneaking ? .on : .off
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Bindings: unavailable"
            return
        }
        statsLabel.stringValue = PlayerLocomotionReadout.bindingsText(
            for: provider.playerLocomotionSnapshot
        )
    }

    @objc private func sneakChanged() {
        provider?.isSneaking = sneakControl.state == .on
        finishInteraction()
    }

    @objc private func jump() {
        provider?.requestJump()
        finishInteraction()
    }
}
