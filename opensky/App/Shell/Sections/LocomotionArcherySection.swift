// World > Player & Locomotion > Archery section (issue #196, roadmap item
// 15.5, scope point 6): the dev spawn control the issue asks for, the live
// projectile count, and the last-trajectory readout, beside the shot state the
// attack button drives.
//
// A section under the existing destination rather than a new one, on the same
// reading item 15.4 made for Melee: archery is four controls on a subsystem the
// Player & Locomotion panel already describes, and the M15 gate panel (item
// 15.9) is where a Combat destination belongs if the surface outgrows this.
// Placing it beside Melee is deliberate — the two share a mouse button, and a
// reader comparing "why did my click swing instead of drawing" wants both
// readouts in one place.
//
// All four controls are momentary, so all four are buttons. There is nothing to
// toggle: drawing a bow is a held input with no state to set from a checkbox
// (the same reasoning that keeps Block out of the Melee section), and the three
// clean-up actions are one-shots. Nothing here is an override, so the section
// registers none: an arrow in the air is world state and a "Reset all" that
// deleted it would undo something the user did on purpose.

import AppKit

final class LocomotionArcherySection: PanelSectionViewController {
    weak var provider: (any ArcheryControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let spawnControl = NSButton(title: "Fire one arrow", target: nil, action: nil)
    let despawnControl = NSButton(title: "Despawn in flight", target: nil, action: nil)
    let clearStuckControl = NSButton(title: "Clear stuck arrows", target: nil, action: nil)
    let clearTraceControl = NSButton(title: "Clear shot trace", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(
        identifier: "LocomotionArcheryStatsLabel"
    )

    override var sectionTitle: String {
        "Archery"
    }

    override var sectionIdentifier: String {
        "locomotionArchery"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureButton(
            spawnControl, target: self, action: #selector(spawn),
            identifier: "ArcherySpawnControl"
        )
        PanelComponents.configureButton(
            despawnControl, target: self, action: #selector(despawn),
            identifier: "ArcheryDespawnControl"
        )
        PanelComponents.configureButton(
            clearStuckControl, target: self, action: #selector(clearStuck),
            identifier: "ArcheryClearStuckControl"
        )
        PanelComponents.configureButton(
            clearTraceControl, target: self, action: #selector(clearTrace),
            identifier: "ArcheryClearTraceControl"
        )
        return [
            PanelComponents.note(
                "With a bow equipped, holding the left mouse button draws and releasing "
                    + "it looses; the graph decides when the arrow actually leaves the "
                    + "string. Fire one arrow takes the same shot from here without "
                    + "spending one from the quiver, so a trajectory can be watched "
                    + "without keeping arrows stocked."
            ),
            PanelComponents.group([
                PanelComponents.buttonRow([spawnControl, despawnControl]),
                PanelComponents.buttonRow([clearStuckControl, clearTraceControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        for control in [spawnControl, despawnControl, clearStuckControl, clearTraceControl] {
            control.isEnabled = provider != nil
        }
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Archery: unavailable"
            return
        }
        let snapshot = provider.archerySnapshot
        statsLabel.stringValue = [
            ArcheryReadout.stateText(for: snapshot),
            ArcheryReadout.equipmentText(for: snapshot),
            ArcheryReadout.flightText(for: snapshot),
            ArcheryReadout.traceText(for: snapshot)
        ].joined(separator: "\n")
    }

    @objc private func spawn() {
        provider?.spawnDevProjectile()
        finishInteraction()
    }

    @objc private func despawn() {
        provider?.despawnProjectiles()
        finishInteraction()
    }

    @objc private func clearStuck() {
        provider?.clearStuckProjectiles()
        finishInteraction()
    }

    @objc private func clearTrace() {
        provider?.clearProjectileTrace()
        finishInteraction()
    }
}
