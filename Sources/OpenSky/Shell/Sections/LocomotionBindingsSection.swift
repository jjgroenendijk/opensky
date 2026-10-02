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
        jumpControl.toolTip = "One jump on solid ground. Hold run or sprint keys to see them here."
        PanelComponents.configureCheckbox(
            sneakControl, target: self, action: #selector(sneakChanged),
            identifier: "LocomotionSneakControl"
        )
        PanelComponents.configureButton(
            jumpControl, target: self, action: #selector(jump),
            identifier: "LocomotionJumpControl"
        )
        return [
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
