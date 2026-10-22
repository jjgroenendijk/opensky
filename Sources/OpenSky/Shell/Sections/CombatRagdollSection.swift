// World > Combat & Physics > Death & Ragdoll section: the ragdoll and dismember
// triggers, with bone-body, constraint-iteration, and death-effect readouts. The
// triggers are buttons; Freeze is a checkbox. No override: a corpse is world state
// the user made.

import AppKit
import OpenSkyCombat
import OpenSkyPhysics

final class CombatRagdollSection: PanelSectionViewController {
    weak var provider: (any RagdollControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let triggerControl = NSButton(title: "Ragdoll selected actor", target: nil, action: nil)
    let clearControl = NSButton(title: "Clear ragdolls", target: nil, action: nil)
    let dismemberControl = NSButton(title: "Dismember selected actor", target: nil, action: nil)
    let freezeControl = NSButton(
        checkboxWithTitle: "Freeze ragdoll stepping", target: nil, action: nil
    )
    let selfCollisionControl = NSButton(
        checkboxWithTitle: "Bones collide with each other", target: nil, action: nil
    )

    private let statsLabel = PanelComponents.statsLabel(
        identifier: "CombatRagdollStatsLabel"
    )

    override var sectionTitle: String {
        "Death & Ragdoll"
    }

    override var sectionIdentifier: String {
        "combatRagdoll"
    }

    override func makeContentViews() -> [NSView] {
        triggerControl.toolTip = "Kills the crosshair target so it falls as a ragdoll."
        dismemberControl.toolTip = "Kills the crosshair target and cuts off its head."
        freezeControl.toolTip = "Stops the bodies where they are."
        selfCollisionControl.toolTip = "Stops limbs from passing through the body."
        PanelComponents.configureButton(
            triggerControl, target: self, action: #selector(trigger),
            identifier: "RagdollTriggerControl"
        )
        PanelComponents.configureButton(
            clearControl, target: self, action: #selector(clear),
            identifier: "RagdollClearControl"
        )
        PanelComponents.configureButton(
            dismemberControl, target: self, action: #selector(dismember),
            identifier: "RagdollDismemberControl"
        )
        PanelComponents.configureCheckbox(
            freezeControl, target: self, action: #selector(toggleFreeze),
            identifier: "RagdollFreezeControl"
        )
        PanelComponents.configureCheckbox(
            selfCollisionControl, target: self, action: #selector(toggleSelfCollision),
            identifier: "RagdollSelfCollisionControl"
        )
        return [
            PanelComponents.group([
                PanelComponents.buttonRow([triggerControl, clearControl]),
                PanelComponents.buttonRow([dismemberControl]),
                freezeControl,
                selfCollisionControl
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        let controls = [
            triggerControl, clearControl, dismemberControl, freezeControl, selfCollisionControl
        ]
        for control in controls {
            control.isEnabled = provider != nil
        }
        let snapshot = provider?.ragdollStatsSnapshot
        freezeControl.state = snapshot?.isFrozen == true ? .on : .off
        selfCollisionControl.state = snapshot?.isSelfCollisionEnabled == true ? .on : .off
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Ragdolls: unavailable"
            return
        }
        let snapshot = provider.ragdollStatsSnapshot
        statsLabel.stringValue = [
            RagdollReadout.ragdollText(for: snapshot),
            RagdollReadout.boneBodyText(for: snapshot),
            RagdollReadout.solverText(for: snapshot),
            RagdollReadout.selfCollisionText(for: snapshot),
            RagdollReadout.recoveryText(for: snapshot),
            provider.deathEffectsText
        ].joined(separator: "\n")
    }

    @objc private func trigger() {
        provider?.triggerRagdoll()
        finishInteraction()
    }

    @objc private func dismember() {
        provider?.dismemberSelectedActor()
        finishInteraction()
    }

    @objc private func clear() {
        provider?.clearRagdolls()
        finishInteraction()
    }

    @objc private func toggleFreeze() {
        provider?.setRagdollFrozen(freezeControl.state == .on)
        finishInteraction()
    }

    @objc private func toggleSelfCollision() {
        provider?.setRagdollSelfCollision(selfCollisionControl.state == .on)
        finishInteraction()
    }
}
