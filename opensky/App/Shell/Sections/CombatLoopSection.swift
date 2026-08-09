// World > Combat & Physics > Combat Loop section (issues #374 and #424, roadmap
// items 15.7 and 16.7; shipped by the M15 gate, issue #198): the hostility
// toggle, and the combat-state, per-fighter, incoming-hit and transient-count
// readouts the loop publishes.
//
// Item 16.7 deleted the "Spawn dev target" and "Reset dev target" buttons with
// the clock they drove. There is nothing to spawn now: making an actor hostile
// and letting it notice the player *is* the fight, so the checkbox that was the
// setup step for the dev target is the whole control surface, and the readout
// that used to describe one clock's phase now describes every fighter's mind.
//
// Hostility is a state the world holds, so it is a checkbox; clearing the trace
// is a one-shot, so it is a button. That is the same split the Melee section
// makes for draw, attack and block.
//
// Not overridden. An angry opponent is world state a user made on purpose, and
// a "Reset all" that calmed the fight would undo it. Clearing the checkbox is
// the deliberate way back.

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
            clearTraceControl, target: self, action: #selector(clearTrace),
            identifier: "CombatClearTraceControl"
        )
        return [
            PanelComponents.note(
                "The selected actor is the nearest resident one, which is also what the "
                    + "Actor Values controls act on. Making it hostile does not by itself "
                    + "start a fight: the actor has to notice the player first, which is "
                    + "the detection pass under World > AI & Navigation. Once it does, it walks "
                    + "over, swings, blocks, breaks off at low health, hunts for a player "
                    + "who broke line of sight and eventually gives up and goes back to its "
                    + "schedule. The Fighters lines below say which of those each actor is "
                    + "doing right now."
            ),
            PanelComponents.group([
                hostilityControl,
                PanelComponents.buttonRow([clearTraceControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        let available = provider != nil
        for control in [hostilityControl, clearTraceControl] {
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
            CombatLoopReadout.actorsText(for: snapshot),
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

    @objc private func clearTrace() {
        provider?.clearCombatTrace()
        finishInteraction()
    }
}
