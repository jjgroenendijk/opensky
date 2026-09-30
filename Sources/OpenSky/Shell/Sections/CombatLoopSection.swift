// World > Combat & Physics > Combat Loop section: the hostility and spell-cast
// checkboxes, and the combat-state, per-fighter, incoming-hit and transient
// readouts. Standing states are checkboxes; clearing the trace is a button.
// Not overridden: an angry opponent is world state the user made, and clearing
// the checkbox is the way back.

import AppKit
import OpenSkyCombat

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
    let castingControl = NSButton(
        checkboxWithTitle: "Fighters cast spells", target: nil, action: nil
    )
    let clearTraceControl = NSButton(title: "Clear hit trace", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(identifier: "CombatLoopStatsLabel")

    override var sectionTitle: String {
        "Combat Loop"
    }

    override var sectionIdentifier: String {
        "combatLoop"
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureCheckbox(
            hostilityControl, target: self, action: #selector(hostilityChanged),
            identifier: "CombatHostilityControl"
        )
        PanelComponents.configureCheckbox(
            castingControl, target: self, action: #selector(castingChanged),
            identifier: "CombatActorCastingControl"
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
            PanelComponents.note(
                "A fighter that knows a hostile spell it can pay for and reach with casts "
                    + "it instead of closing, and casts about half the time when it is "
                    + "already in weapon reach. Clearing \"Fighters cast spells\" keeps "
                    + "every fighter on its fists, which is how a swing that was chosen "
                    + "over a cast is told apart from an actor that had nothing castable."
            ),
            PanelComponents.group([
                hostilityControl,
                castingControl,
                PanelComponents.buttonRow([clearTraceControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        let available = provider != nil
        for control in [hostilityControl, castingControl, clearTraceControl] {
            control.isEnabled = available
        }
        hostilityControl.state = provider?.selectedActorIsHostile == true ? .on : .off
        castingControl.state = provider?.isActorCastingEnabled == true ? .on : .off
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
            CombatLoopReadout.castingText(for: snapshot),
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

    @objc private func castingChanged() {
        provider?.isActorCastingEnabled = castingControl.state == .on
        finishInteraction()
    }

    @objc private func clearTrace() {
        provider?.clearCombatTrace()
        finishInteraction()
    }
}
