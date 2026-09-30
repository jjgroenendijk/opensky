// World > Player & Locomotion > Bindings section: every gameplay key with its
// live state, so no behavior needs an unadvertised key. Sneak is a toggle; jump
// is a button that requests one jump. Sprint and run are held modifiers, so
// they are listed live instead. Not overridden.

import AppKit
import OpenSkyWorld

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
