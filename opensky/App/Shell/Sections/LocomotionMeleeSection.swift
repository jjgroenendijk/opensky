// World > Player & Locomotion > Melee section (issue #195, roadmap item 15.4):
// the three keys this item added, listed with their live state and reachable
// from a control, plus the weapon, reach and last-hit readouts.
//
// A section under the existing destination rather than a new one, per the
// app-ui placement rule: melee is four controls on a subsystem the Player &
// Locomotion panel already describes, and the M15 gate panel (item 15.9) is
// where a Combat destination belongs if the surface outgrows this.
//
// Draw/sheath is a real toggle, so it is a checkbox; attack is momentary, so it
// is a button that requests exactly one swing, the same latch the mouse sets.
// Block is a held modifier with nothing to latch — a checkbox would assert it
// for a single frame and read as broken — so it is reported live in the state
// readout instead. That is the same three-way split `LocomotionBindingsSection`
// already makes for sneak, jump, and run/sprint.
//
// Not overridden. A drawn weapon is world state, not a panel setting, and a
// "Reset all" that sheathed it would undo something the user did on purpose.

import AppKit

final class LocomotionMeleeSection: PanelSectionViewController {
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
        identifier: "LocomotionMeleeStatsLabel"
    )

    override var sectionTitle: String {
        "Melee"
    }

    override var sectionIdentifier: String {
        "locomotionMelee"
    }

    var readout: String {
        statsLabel.stringValue
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
            MeleeCombatReadout.traceText(for: snapshot)
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
