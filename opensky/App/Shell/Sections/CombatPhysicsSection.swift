// World > Combat & Physics > Physics section (issue #193, roadmap item 15.2,
// scope point 7; shipped by the M15 gate, issue #198): the body counts the
// dynamic simulation publishes, with the freeze and reset controls
// `PhysicsControlProviding` was specified against.
//
// Freeze is a state and so is a checkbox; reset is a one-shot and so is a
// button. The counts are the whole readout: a developer watching clutter settle
// wants to know how many bodies exist, how many the solver is still paying for,
// and how much a step cost, and none of those is legible from the picture.
//
// Not overridden. Where a crate has fallen to is world state a player put it
// in, and a "Reset all" that stood every barrel back up would undo it. The
// freeze *is* a panel state that outlives the panel, so the section resets it
// deliberately — a session left with the physics frozen looks broken and reads
// as a bug in the simulation rather than as a control someone left on.

import AppKit

final class CombatPhysicsSection: PanelSectionViewController {
    weak var provider: (any PhysicsControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let freezeControl = NSButton(
        checkboxWithTitle: "Freeze body stepping", target: nil, action: nil
    )
    let resetControl = NSButton(title: "Reset bodies", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(identifier: "CombatPhysicsStatsLabel")

    override var sectionTitle: String {
        "Physics"
    }

    override var sectionIdentifier: String {
        "combatPhysics"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    /// A frozen simulation is the one thing under this destination that sits
    /// away from its default and that a "Reset all" should release.
    static func isOverridden(provider: (any PhysicsControlProviding)?) -> Bool {
        provider?.dynamicBodyStatsSnapshot.isFrozen == true
    }

    static func resetToDefaults(provider: (any PhysicsControlProviding)?) {
        provider?.setPhysicsFrozen(false)
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureCheckbox(
            freezeControl, target: self, action: #selector(toggleFreeze),
            identifier: "PhysicsFreezeControl"
        )
        PanelComponents.configureButton(
            resetControl, target: self, action: #selector(reset),
            identifier: "PhysicsResetControl"
        )
        return [
            PanelComponents.note(
                "Movable clutter is simulated where its NIF carries a dynamic Havok body. "
                    + "Walking into one shoves it, and a body that stops moving falls asleep "
                    + "and stops costing anything until something wakes it. Freeze suspends "
                    + "integration with everything where it is, for inspecting a scene "
                    + "mid-fall; Reset puts every body back at the pose its cell placed it "
                    + "at and clears its velocity."
            ),
            PanelComponents.group([
                freezeControl,
                PanelComponents.buttonRow([resetControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        freezeControl.isEnabled = provider != nil
        resetControl.isEnabled = provider != nil
        freezeControl.state = provider?.dynamicBodyStatsSnapshot.isFrozen == true ? .on : .off
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Bodies: unavailable"
            return
        }
        let snapshot = provider.dynamicBodyStatsSnapshot
        statsLabel.stringValue = [
            PhysicsReadout.bodyText(for: snapshot),
            PhysicsReadout.stepText(for: snapshot),
            PhysicsReadout.recoveryText(for: snapshot)
        ].joined(separator: "\n")
    }

    // MARK: - Actions

    @objc private func toggleFreeze() {
        provider?.setPhysicsFrozen(freezeControl.state == .on)
        finishInteraction()
        refreshOverrideState()
    }

    @objc private func reset() {
        provider?.resetDynamicBodies()
        finishInteraction()
    }
}
