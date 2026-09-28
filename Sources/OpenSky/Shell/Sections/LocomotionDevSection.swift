// World > Player & Locomotion > Dev Controls section (issue #191): hold one
// gait, and raise one graph event by hand.
//
// Both controls exist so a state the route is awkward to reach can still be
// inspected: swimming needs water under the capsule, landing needs a fall, and
// a graph event the bridge only raises on an edge is otherwise a single frame
// long. Forcing a gait writes the graph's own inputs and the resolved speed and
// touches nothing else — the capsule keeps its gravity, its grounding and its
// collision — so a forced swim shows the swim clips on dry land rather than
// pretending the world changed.
//
// This section carries the destination's overridden-ness: a held gait is a
// setting that differs from the documented default, and it is what the
// sidebar's "Reset all" clears. Raising an event leaves nothing behind and is
// therefore not an override.

import AppKit

final class LocomotionDevSection: PanelSectionViewController {
    weak var provider: (any PlayerLocomotionControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let forcedGaitControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let clearForcedGaitControl = NSButton(title: "Clear", target: nil, action: nil)
    let eventControl = NSComboBox()
    let raiseEventControl = NSButton(title: "Raise event", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(
        identifier: "LocomotionDevStatsLabel"
    )
    /// What the last raise did, worded for the readout. Held here rather than
    /// in the engine because it describes a panel action, not world state.
    private var lastEvent: String?

    /// The popup's rows: "none" first, then every gait the bridge can resolve.
    private let gaits: [LocomotionGait] = [.walk, .run, .sprint, .sneak, .swim]

    override var sectionTitle: String {
        "Dev Controls"
    }

    override var sectionIdentifier: String {
        "locomotionDev"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    static func isOverridden(provider: (any PlayerLocomotionControlProviding)?) -> Bool {
        provider?.forcedLocomotionGait != nil
    }

    static func resetToDefaults(provider: (any PlayerLocomotionControlProviding)?) {
        provider?.forcedLocomotionGait = nil
    }

    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        configureControls()
        return [
            PanelComponents.note(
                "A forced gait holds the graph's movement inputs and the resolved speed. It "
                    + "does not move the capsule into water or off the ground, so the "
                    + "controller's own gravity and collision still decide where the player "
                    + "ends up."
            ),
            PanelComponents.group([
                forcedGaitControl,
                PanelComponents.buttonRow([clearForcedGaitControl])
            ]),
            PanelComponents.group([
                PanelComponents.note(
                    "The event names are the ones the bridge raises on its own edges. A name "
                        + "the graph does not declare is reported as such rather than dropped."
                ),
                PanelComponents.labeledFieldRow(
                    caption: "Event", captionWidth: 70, field: eventControl
                ),
                PanelComponents.buttonRow([raiseEventControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        let available = provider != nil
        forcedGaitControl.isEnabled = available
        clearForcedGaitControl.isEnabled = available
        eventControl.isEnabled = available
        raiseEventControl.isEnabled = available
        guard let provider else { return }
        let forced = provider.forcedLocomotionGait
        let row = forced.flatMap { gaits.firstIndex(of: $0).map { $0 + 1 } } ?? 0
        forcedGaitControl.selectItem(at: row)
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Dev controls: unavailable"
            return
        }
        statsLabel.stringValue = PlayerLocomotionReadout.devText(
            for: provider.playerLocomotionSnapshot, lastEvent: lastEvent
        )
    }

    // MARK: - Actions

    @objc private func forcedGaitChanged() {
        let row = forcedGaitControl.indexOfSelectedItem
        provider?.forcedLocomotionGait = gaits.indices.contains(row - 1) ? gaits[row - 1] : nil
        finishInteraction()
    }

    @objc private func clearForcedGait() {
        provider?.forcedLocomotionGait = nil
        syncControls()
        finishInteraction()
    }

    @objc private func raiseEvent() {
        let name = eventControl.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            lastEvent = "no event name entered"
            finishInteraction()
            return
        }
        let declared = provider?.raiseLocomotionEvent(named: name) ?? false
        lastEvent = declared
            ? "\(name) raised"
            : "\(name) — the graph declares no such event"
        finishInteraction()
    }

    // MARK: - Setup

    private func configureControls() {
        forcedGaitControl.addItem(withTitle: "No forced gait")
        for gait in gaits {
            forcedGaitControl.addItem(withTitle: gait.rawValue.capitalized)
        }
        PanelComponents.configurePopUp(
            forcedGaitControl, target: self, action: #selector(forcedGaitChanged),
            identifier: "LocomotionForcedGaitControl"
        )
        PanelComponents.configureButton(
            clearForcedGaitControl, target: self, action: #selector(clearForcedGait),
            identifier: "LocomotionClearForcedGaitControl"
        )
        PanelComponents.configureComboBox(
            eventControl, target: self, action: #selector(raiseEvent),
            identifier: "LocomotionEventControl", width: 180
        )
        eventControl.addItems(withObjectValues: LocomotionGraphNames.events)
        eventControl.stringValue = LocomotionGraphNames.moveStart
        PanelComponents.configureButton(
            raiseEventControl, target: self, action: #selector(raiseEvent),
            identifier: "LocomotionRaiseEventControl"
        )
    }
}
