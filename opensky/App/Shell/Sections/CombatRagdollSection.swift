// World > Player & Locomotion > Death & Ragdoll section (issue #197, roadmap
// item 15.6, scope point 7): the ragdoll trigger the issue asks for, with the
// bone-body and constraint-iteration readouts beside it.
//
// A section under the existing destination rather than a new one, on the same
// reading items 15.4 and 15.5 made for Melee and Archery: this is three controls
// on a subsystem the Player & Locomotion panel already describes, and the M15
// gate panel (item 15.9) is where a Combat & Physics destination belongs if the
// surface outgrows this. Placing it beside Melee and Archery is deliberate — a
// reader who has just watched an arrow land wants to see what killing the target
// did, in the same panel.
//
// Trigger is momentary and so is Clear; Freeze is a state and so is a checkbox.
// Nothing here is an override, so the section registers none: a corpse on the
// floor is world state a user made on purpose, and a "Reset all" that resurrected
// it would undo that.

import AppKit

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
    let freezeControl = NSButton(
        checkboxWithTitle: "Freeze ragdoll stepping", target: nil, action: nil
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

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureButton(
            triggerControl, target: self, action: #selector(trigger),
            identifier: "RagdollTriggerControl"
        )
        PanelComponents.configureButton(
            clearControl, target: self, action: #selector(clear),
            identifier: "RagdollClearControl"
        )
        PanelComponents.configureCheckbox(
            freezeControl, target: self, action: #selector(toggleFreeze),
            identifier: "RagdollFreezeControl"
        )
        return [
            PanelComponents.note(
                "An actor whose health reaches zero raises the death events its behavior "
                    + "graph declares, and the graph decides which frame the physics takes "
                    + "the skeleton over on. Ragdoll selected actor takes the crosshair "
                    + "target down the same route without waiting for the fight, so a "
                    + "collapse can be watched on demand. Freeze suspends the joint solver "
                    + "with the corpses where they are, for inspecting a pose mid-fall."
            ),
            PanelComponents.group([
                PanelComponents.buttonRow([triggerControl, clearControl]),
                freezeControl
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        for control in [triggerControl, clearControl, freezeControl] {
            control.isEnabled = provider != nil
        }
        freezeControl.state = provider?.ragdollStatsSnapshot.isFrozen == true ? .on : .off
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
            RagdollReadout.recoveryText(for: snapshot)
        ].joined(separator: "\n")
    }

    @objc private func trigger() {
        provider?.triggerRagdoll()
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
}
