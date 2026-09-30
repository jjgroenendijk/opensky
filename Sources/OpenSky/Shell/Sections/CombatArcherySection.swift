// World > Player & Locomotion > Archery section: the dev spawn control, the
// live projectile count, and the last-trajectory readout. It sits beside Melee,
// because both share a mouse button. All controls are one-shot buttons, and the
// section registers no override: an arrow in flight is world state.

import AppKit
import OpenSkyCombat

final class CombatArcherySection: PanelSectionViewController {
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
        identifier: "CombatArcheryStatsLabel"
    )

    override var sectionTitle: String {
        "Archery"
    }

    override var sectionIdentifier: String {
        "combatArchery"
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
            ArcheryReadout.traceText(for: snapshot),
            ArcheryReadout.settingsText(for: snapshot)
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
