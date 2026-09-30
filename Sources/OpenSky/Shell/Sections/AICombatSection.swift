// World > AI & Navigation > Combat Behavior section: hostility for the selected
// actor and its behavior readout. The Combat Loop section's checkbox targets
// the nearest actor instead; both write `ActorCombatState`, so they agree.
// Not overridden: clearing the checkbox is the way back.

import AppKit
import OpenSkyCombat
import OpenSkyWorld

final class AICombatSection: PanelSectionViewController {
    weak var provider: (any CombatLoopControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    weak var selectionProvider: (any AINavigationControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let hostilityControl = NSButton(
        checkboxWithTitle: "Selected actor is hostile", target: nil, action: nil
    )

    private let statsLabel = PanelComponents.statsLabel(identifier: "AICombatStatsLabel")

    override var sectionTitle: String {
        "Combat Behavior"
    }

    override var sectionIdentifier: String {
        "aiCombat"
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureCheckbox(
            hostilityControl, target: self, action: #selector(hostilityChanged),
            identifier: "AIHostilityControl"
        )
        return [
            PanelComponents.note(
                "Making the selected actor hostile does not start a fight on its own: it has "
                    + "to perceive the player first, which is the Detection section below. "
                    + "Once it does it closes, spaces itself, swings, blocks, breaks off at "
                    + "low health, hunts for a player who broke line of sight and eventually "
                    + "gives up and returns to its package. The phase line says which of "
                    + "those it is doing right now."
            ),
            PanelComponents.group([hostilityControl]),
            statsLabel
        ]
    }

    override func syncControls() {
        hostilityControl.isEnabled = selectionProvider != nil
        hostilityControl.state =
            selectionProvider?.selectedAIActorIsHostile == true ? .on : .off
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Combat: unavailable"
            return
        }
        let snapshot = provider.combatLoopSnapshot
        let selection = selectionProvider?.aiNavigationSnapshot ?? .unavailable
        statsLabel.stringValue = [
            CombatLoopReadout.stateText(for: snapshot),
            Self.selectedText(for: selection, snapshot: snapshot),
            CombatLoopReadout.actorsText(for: snapshot)
        ].joined(separator: "\n")
    }

    /// The selected actor's own line, lifted out of the fighter list so the
    /// actor this destination is following is legible without reading a crowd.
    nonisolated static func selectedText(
        for selection: AINavigationSnapshot,
        snapshot: CombatLoopSnapshot
    ) -> String {
        let name = selection.selectedActorName
        let regard = selection.selectedActorIsHostile ? "hostile" : "neutral"
        guard
            let key = selection.selectedActor,
            let actor = snapshot.actors.first(where: { $0.key == key })
        else {
            return "Selected: \(name) is \(regard), not in a fight"
        }
        return "Selected: \(name) is \(regard) — " + CombatLoopReadout.actorLine(for: actor)
    }

    // MARK: - Actions

    @objc private func hostilityChanged() {
        selectionProvider?.selectedAIActorIsHostile = hostilityControl.state == .on
        finishInteraction()
    }
}
