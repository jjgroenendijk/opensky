// World > Combat & Physics > Combat Loop section (issue #374, roadmap item
// 15.7, scope point 7; shipped by the M15 gate, issue #198): the hostility
// toggle, the dev-target spawn and reset controls, and the combat-state,
// incoming-hit and transient-count readouts the loop publishes.
//
// Hostility is a state the world holds, so it is a checkbox; spawning and
// resetting the opponent and clearing the trace are one-shots, so they are
// buttons. That is the same three-way split the Melee section makes for draw,
// attack and block.
//
// Not overridden. An angry opponent is world state a user made on purpose, and
// a "Reset all" that calmed the fight would undo it. `CombatResetDevTargetControl`
// is the deliberate way back.

import AppKit

final class CombatLoopSection: PanelSectionViewController {
    weak var provider: (any CombatLoopControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let hostilityControl = NSButton(
        checkboxWithTitle: "Selected actor is hostile", target: nil, action: nil
    )
    let spawnControl = NSButton(title: "Spawn dev target", target: nil, action: nil)
    let resetControl = NSButton(title: "Reset dev target", target: nil, action: nil)
    let clearTraceControl = NSButton(title: "Clear hit trace", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(identifier: "CombatLoopStatsLabel")

    override var sectionTitle: String {
        "Combat Loop"
    }

    override var sectionIdentifier: String {
        "combatLoop"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureCheckbox(
            hostilityControl, target: self, action: #selector(hostilityChanged),
            identifier: "CombatHostilityControl"
        )
        PanelComponents.configureButton(
            spawnControl, target: self, action: #selector(spawn),
            identifier: "CombatSpawnDevTargetControl"
        )
        PanelComponents.configureButton(
            resetControl, target: self, action: #selector(resetTarget),
            identifier: "CombatResetDevTargetControl"
        )
        PanelComponents.configureButton(
            clearTraceControl, target: self, action: #selector(clearTrace),
            identifier: "CombatClearTraceControl"
        )
        return [
            PanelComponents.note(
                "The selected actor is the nearest resident one, which is also what the "
                    + "Actor Values controls act on. Making it hostile puts the player in "
                    + "combat; Spawn dev target additionally starts its attack clock, so it "
                    + "swings on its own and the blows land on the live HUD bars. Reset "
                    + "stops the clock and calms it. There is no NPC combat AI yet — the "
                    + "opponent is a fixed-interval attacker, and the readout says which "
                    + "phase of that clock it is in."
            ),
            PanelComponents.group([
                hostilityControl,
                PanelComponents.buttonRow([spawnControl, resetControl]),
                PanelComponents.buttonRow([clearTraceControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        let available = provider != nil
        for control in [hostilityControl, spawnControl, resetControl, clearTraceControl] {
            control.isEnabled = available
        }
        hostilityControl.state = provider?.selectedActorIsHostile == true ? .on : .off
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Combat: unavailable"
            return
        }
        let snapshot = provider.combatLoopSnapshot
        statsLabel.stringValue = [
            CombatLoopReadout.stateText(for: snapshot),
            CombatLoopReadout.devTargetText(for: snapshot),
            CombatLoopReadout.hostilityText(for: snapshot),
            CombatLoopReadout.incomingText(for: snapshot),
            CombatLoopReadout.transientText(for: snapshot),
            snapshot.lastActionText
        ].joined(separator: "\n")
    }

    // MARK: - Actions

    @objc private func hostilityChanged() {
        provider?.selectedActorIsHostile = hostilityControl.state == .on
        finishInteraction()
    }

    @objc private func spawn() {
        provider?.spawnCombatDevTarget()
        finishInteraction()
    }

    @objc private func resetTarget() {
        provider?.resetCombatDevTarget()
        finishInteraction()
    }

    @objc private func clearTrace() {
        provider?.clearCombatTrace()
        finishInteraction()
    }
}
