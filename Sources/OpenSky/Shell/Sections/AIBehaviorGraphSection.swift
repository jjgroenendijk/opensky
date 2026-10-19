// World > AI & Navigation > Behaviour Graphs: the switch and the distance cutoff for
// the graph each NPC and creature runs, and the selected actor's active states and events.

import AppKit
import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyFormatsESM

final class AIBehaviorGraphSection: PanelSectionViewController {
    weak var provider: (any ActorGraphControlProviding)? {
        didSet { reloadIfLoaded() }
    }

    weak var selectionProvider: (any AINavigationControlProviding)? {
        didSet { reloadIfLoaded() }
    }

    let enabledControl = NSButton(
        checkboxWithTitle: "Actors run their own graphs", target: nil, action: nil
    )
    let fullRateControl = NSSlider(
        value: 2048, minValue: 0, maxValue: 8192, target: nil, action: nil
    )
    let distanceControl = NSSlider(
        value: 6144, minValue: 0, maxValue: 16384, target: nil, action: nil
    )
    let eventControl = NSTextField(string: "")
    let sendControl = NSButton(title: "Send event", target: nil, action: nil)

    private let fullRateLabel = PanelComponents.valueLabel(width: 90)
    private let distanceLabel = PanelComponents.valueLabel(width: 90)
    private let statsLabel = PanelComponents.statsLabel(identifier: "ActorGraphStatsLabel")

    override var sectionTitle: String {
        "Behaviour Graphs"
    }

    override var sectionIdentifier: String {
        "aiBehaviorGraphs"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    static func isOverridden(provider: (any ActorGraphControlProviding)?) -> Bool {
        guard let snapshot = provider?.actorGraphSnapshot(for: nil) else { return false }
        return !snapshot.isEnabled || snapshot.cutoff != .standard
    }

    static func resetToDefaults(provider: (any ActorGraphControlProviding)?) {
        provider?.setActorGraphsEnabled(true)
        provider?.setActorGraphCutoff(.standard)
    }

    override func makeContentViews() -> [NSView] {
        enabledControl.toolTip = "Each NPC and creature plays its race's behaviour graph."
        fullRateControl.toolTip = "Graphs this close to the camera update every frame."
        distanceControl.toolTip = "Graphs past this distance stop updating and hold their pose."
        eventControl.toolTip = "A graph event, such as moveStart."
        sendControl.toolTip = "Sends the event to the selected actor's graph."
        PanelComponents.configureCheckbox(
            enabledControl, target: self, action: #selector(enabledChanged),
            identifier: "ActorGraphEnabledControl"
        )
        PanelComponents.configureSlider(
            fullRateControl, target: self, action: #selector(cutoffChanged),
            identifier: "ActorGraphFullRateControl", width: 174
        )
        PanelComponents.configureSlider(
            distanceControl, target: self, action: #selector(cutoffChanged),
            identifier: "ActorGraphDistanceControl", width: 174
        )
        PanelComponents.configureTextField(
            eventControl, identifier: "ActorGraphEventControl", width: PanelMetrics.contentWidth
        )
        PanelComponents.configureButton(
            sendControl, target: self, action: #selector(send),
            identifier: "ActorGraphSendControl"
        )
        return [
            PanelComponents.group([
                enabledControl,
                PanelComponents.sliderRow(slider: fullRateControl, valueLabel: fullRateLabel),
                PanelComponents.sliderRow(slider: distanceControl, valueLabel: distanceLabel)
            ]),
            PanelComponents.group([eventControl, PanelComponents.buttonRow([sendControl])]),
            statsLabel
        ]
    }

    override func syncControls() {
        let snapshot = provider?.actorGraphSnapshot(for: nil)
        let available = snapshot != nil
        for control in [enabledControl, fullRateControl, distanceControl] {
            control.isEnabled = available
        }
        enabledControl.state = snapshot?.isEnabled ?? true ? .on : .off
        let cutoff = snapshot?.cutoff ?? .standard
        fullRateControl.floatValue = cutoff.fullRateDistance
        distanceControl.floatValue = cutoff.maximumDistance
        sendControl.isEnabled = available && selectionProvider?.selectedAIActor != nil
        updateLabels()
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Behaviour graphs: unavailable"
            return
        }
        let snapshot = provider.actorGraphSnapshot(for: selectionProvider?.selectedAIActor)
        statsLabel.stringValue = ActorGraphReadoutText.lines(for: snapshot)
            .joined(separator: "\n")
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
        syncControls()
    }

    private func updateLabels() {
        fullRateLabel.stringValue = "\(Int(fullRateControl.floatValue)) units"
        distanceLabel.stringValue = "\(Int(distanceControl.floatValue)) units"
    }

    private func reloadIfLoaded() {
        guard isViewLoaded else { return }
        syncControls()
        refreshReadout()
    }

    @objc private func enabledChanged() {
        provider?.setActorGraphsEnabled(enabledControl.state == .on)
        refreshOverrideState()
        finishInteraction()
    }

    @objc private func cutoffChanged() {
        provider?.setActorGraphCutoff(ActorGraphCutoff(
            fullRateDistance: fullRateControl.floatValue,
            maximumDistance: distanceControl.floatValue
        ))
        updateLabels()
        refreshOverrideState()
        finishInteraction(refocusOnMouseUpOnly: true)
    }

    @objc private func send() {
        let event = eventControl.stringValue.trimmingCharacters(in: .whitespaces)
        guard !event.isEmpty, let actor = selectionProvider?.selectedAIActor else { return }
        provider?.sendActorGraphEvent(event, to: actor)
        refreshReadout()
        finishInteraction()
    }
}

/// The readout lines of the Behaviour Graphs section.
enum ActorGraphReadoutText {
    static func lines(for snapshot: ActorGraphControlSnapshot) -> [String] {
        guard snapshot.isEnabled else { return ["Behaviour graphs: off"] }
        var lines = [
            "Running: \(snapshot.runningCount)",
            "Stepped: \(snapshot.fullRateCount) full, \(snapshot.reducedRateCount) reduced"
        ]
        lines += snapshot.failures.prefix(3).map { "Failed: \($0)" }
        guard let selected = snapshot.selected else {
            lines.append("Selected: no graph")
            return lines
        }
        lines.append("Graph: \(selected.project)")
        lines.append("Rate: \(selected.rate.rawValue) · steps \(selected.steps)")
        lines.append("States: " + (selected.activeStates.isEmpty
                ? "none" : selected.activeStates.joined(separator: " > ")))
        lines.append("Events: " + (selected.recentEvents.isEmpty
                ? "none" : selected.recentEvents.suffix(6).joined(separator: ", ")))
        return lines
    }
}
