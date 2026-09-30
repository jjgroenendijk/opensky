// World > Player & Locomotion > Melee section: the melee keys with their live
// state, plus the weapon, reach, and last-hit readouts. Draw is a checkbox and
// attack is a button. Block is a held modifier, so it is shown in the readout.
// No override: a drawn weapon is world state.

import AppKit
import OpenSkyCombat

final class CombatMeleeSection: PanelSectionViewController {
    weak var provider: (any MeleeCombatControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let weaponDrawnControl = NSButton(
        checkboxWithTitle: "Weapon drawn", target: nil, action: nil
    )
    let attackControl = NSButton(title: "Attack", target: nil, action: nil)
    let clearTraceControl = NSButton(title: "Clear hit trace", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(
        identifier: "CombatMeleeStatsLabel"
    )

    override var sectionTitle: String {
        "Melee"
    }

    override var sectionIdentifier: String {
        "combatMelee"
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureCheckbox(
            weaponDrawnControl, target: self, action: #selector(weaponDrawnChanged),
            identifier: "MeleeWeaponDrawnControl"
        )
        PanelComponents.configureButton(
            attackControl, target: self, action: #selector(attack),
            identifier: "MeleeAttackControl"
        )
        PanelComponents.configureButton(
            clearTraceControl, target: self, action: #selector(clearTrace),
            identifier: "MeleeClearTraceControl"
        )
        return [
            PanelComponents.note(
                "R draws and sheathes, the left mouse button attacks, and the right mouse "
                    + "button holds a block. Block is a held modifier with no state to set "
                    + "from here; hold the button and watch the row below say so. Attack "
                    + "requests exactly one swing, which the graph runs only with the "
                    + "weapon drawn."
            ),
            PanelComponents.group([
                weaponDrawnControl,
                PanelComponents.buttonRow([attackControl, clearTraceControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        weaponDrawnControl.isEnabled = provider != nil
        attackControl.isEnabled = provider != nil
        clearTraceControl.isEnabled = provider != nil
        guard let provider else { return }
        weaponDrawnControl.state = provider.isWeaponDrawn ? .on : .off
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Melee: unavailable"
            return
        }
        let snapshot = provider.meleeCombatSnapshot
        statsLabel.stringValue = [
            MeleeCombatReadout.stateText(for: snapshot),
            MeleeCombatReadout.weaponText(for: snapshot),
            MeleeCombatReadout.handsText(for: snapshot),
            MeleeCombatReadout.traceText(for: snapshot),
            MeleeCombatReadout.settingsText(for: snapshot)
        ].joined(separator: "\n")
    }

    @objc private func weaponDrawnChanged() {
        provider?.isWeaponDrawn = weaponDrawnControl.state == .on
        finishInteraction()
    }

    @objc private func attack() {
        provider?.requestMeleeAttack()
        finishInteraction()
    }

    @objc private func clearTrace() {
        provider?.clearMeleeTrace()
        finishInteraction()
    }
}
