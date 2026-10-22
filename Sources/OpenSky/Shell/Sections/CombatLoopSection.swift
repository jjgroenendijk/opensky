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
    let temperamentControl = NSButton(
        checkboxWithTitle: "Confidence and Assistance", target: nil, action: nil
    )
    let gameSettingsControl = NSButton(
        checkboxWithTitle: "Game combat settings", target: nil, action: nil
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
        hostilityControl.toolTip = "The actor fights only after it detects the player."
        castingControl.toolTip = "Off keeps every fighter on weapons only."
        temperamentControl.toolTip = "Confidence decides who fights or flees; allies join fights."
        PanelComponents.configureCheckbox(
            temperamentControl, target: self, action: #selector(temperamentChanged),
            identifier: "CombatTemperamentControl"
        )
        gameSettingsControl.toolTip = "New fights use the install's advance, range, heal, shout, "
            + "and flight settings."
        PanelComponents.configureCheckbox(
            gameSettingsControl, target: self, action: #selector(gameSettingsChanged),
            identifier: "CombatGameSettingsControl"
        )
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
            PanelComponents.group([
                hostilityControl,
                castingControl,
                temperamentControl,
                gameSettingsControl,
                PanelComponents.buttonRow([clearTraceControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        let available = provider != nil
        let controls = [
            hostilityControl, castingControl, temperamentControl, gameSettingsControl,
            clearTraceControl
        ]
        for control in controls {
            control.isEnabled = available
        }
        gameSettingsControl.state = provider?.appliesCombatGameSettings == false ? .off : .on
        hostilityControl.state = provider?.selectedActorIsHostile == true ? .on : .off
        castingControl.state = provider?.isActorCastingEnabled == true ? .on : .off
        temperamentControl.state = provider?.usesCombatTemperament == false ? .off : .on
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
            CombatLoopReadout.alliesText(for: snapshot),
            CombatLoopReadout.castingText(for: snapshot),
            CombatLoopReadout.hostilityText(for: snapshot),
            CombatLoopReadout.temperamentText(for: snapshot),
            CombatLoopReadout.combatAIText(for: snapshot),
            provider.selectedCombatStyle.map {
                "\($0.styleText)\n\($0.settingsText)\n"
                    + $0.gameSettingsText(
                        snapshot.combatAI, isOn: provider.appliesCombatGameSettings
                    )
            } ?? "Style: none",
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

    @objc private func temperamentChanged() {
        provider?.usesCombatTemperament = temperamentControl.state == .on
        finishInteraction()
    }

    @objc private func gameSettingsChanged() {
        provider?.appliesCombatGameSettings = gameSettingsControl.state == .on
        finishInteraction()
    }

    @objc private func clearTrace() {
        provider?.clearCombatTrace()
        finishInteraction()
    }
}
