// World > Combat & Physics > Physics section: the dynamic simulation's body
// counts and step cost, with freeze (a checkbox) and reset (a button). Where a
// crate fell is world state, so "Reset all" leaves it. The freeze is reset,
// because a session left frozen looks like a simulation bug.

import AppKit
import OpenSkyPhysics

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

    override func makeContentViews() -> [NSView] {
        freezeControl.toolTip = "Stops every body where it is."
        resetControl.toolTip = "Puts every body back at its placed pose."
        PanelComponents.configureCheckbox(
            freezeControl, target: self, action: #selector(toggleFreeze),
            identifier: "PhysicsFreezeControl"
        )
        PanelComponents.configureButton(
            resetControl, target: self, action: #selector(reset),
            identifier: "PhysicsResetControl"
        )
        return [
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
