// World > Player & Locomotion > Dev Controls section: hold one gait, or raise
// one graph event, to inspect hard-to-reach states. A forced gait writes only
// the graph inputs and speed, so a forced swim plays swim clips on dry land. A
// held gait is this destination's override; raising an event is not.

import AppKit
import OpenSkyPhysics
import OpenSkyWorld

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

    override func makeContentViews() -> [NSView] {
        forcedGaitControl.toolTip =
            "Forces walk, run, or sprint. Gravity and collision still apply."
        eventControl.toolTip = "Sends an animation event. An unknown name is reported."
        configureControls()
        return [
            PanelComponents.group([
                forcedGaitControl,
                PanelComponents.buttonRow([clearForcedGaitControl])
            ]),
            PanelComponents.group([
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
