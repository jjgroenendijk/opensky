// World > Environment > Actor animation: enable toggle and playback readout, the
// flicker and pulse of placed lights, and the clip events that reach the engine.

import AppKit
import OpenSkyWorld

final class AnimationSection: PanelSectionViewController {
    weak var provider: (any AnimationControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let enabledControl = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    let lightsControl = NSButton(
        checkboxWithTitle: "Flickering lights", target: nil, action: nil
    )
    let eventsControl = NSButton(checkboxWithTitle: "Animation events", target: nil, action: nil)
    let eventField = NSTextField(string: "")
    let sendEventControl = NSButton(title: "Send as player", target: nil, action: nil)
    private let statsLabel = PanelComponents.statsLabel(identifier: "AnimationStatsLabel")
    private let eventsLabel = PanelComponents.statsLabel(identifier: "AnimationEventsStatsLabel")
    private var sendResult = "Sent: none"

    override var sectionTitle: String {
        "Actor animation"
    }

    override var sectionIdentifier: String {
        "animation"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    static func isOverridden(provider: (any AnimationControlProviding)?) -> Bool {
        provider?.actorAnimationsEnabled == false || provider?.lightAnimationEnabled == false
            || provider?.animationEventsEnabled == false
    }

    static func resetToDefaults(provider: (any AnimationControlProviding)?) {
        provider?.actorAnimationsEnabled = true
        provider?.lightAnimationEnabled = true
        provider?.animationEventsEnabled = true
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureCheckbox(
            enabledControl, target: self, action: #selector(enabledChanged),
            identifier: "AnimationsEnabledControl"
        )
        PanelComponents.configureCheckbox(
            lightsControl, target: self, action: #selector(lightsChanged),
            identifier: "LightAnimationEnabledControl"
        )
        eventsControl.toolTip = "Clip events play sounds, shake the camera, and stop head turns."
        PanelComponents.configureCheckbox(
            eventsControl, target: self, action: #selector(eventsChanged),
            identifier: "AnimationEventsEnabledControl"
        )
        PanelComponents.configureTextField(
            eventField, identifier: "AnimationEventNameControl", width: 220,
            placeholder: "CameraShake.0.5"
        )
        sendEventControl.toolTip = "Runs the event at the player, as if the player's clip sent it."
        PanelComponents.configureButton(
            sendEventControl, target: self, action: #selector(sendEvent),
            identifier: "AnimationEventSendControl"
        )
        return [
            PanelComponents.group([enabledControl, lightsControl]),
            statsLabel,
            PanelComponents.group([
                eventsControl,
                PanelComponents.labeledFieldRow(
                    caption: "Event", captionWidth: 60, field: eventField
                ),
                PanelComponents.buttonRow([sendEventControl])
            ]),
            eventsLabel
        ]
    }

    override func syncControls() {
        enabledControl.isEnabled = provider != nil
        enabledControl.state = provider?.actorAnimationsEnabled == true ? .on : .off
        lightsControl.isEnabled = provider != nil
        lightsControl.state = provider?.lightAnimationEnabled == true ? .on : .off
        eventsControl.isEnabled = provider != nil
        eventsControl.state = provider?.animationEventsEnabled == true ? .on : .off
        sendEventControl.isEnabled = provider != nil
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Animation: unavailable"
            eventsLabel.stringValue = "Animation events: unavailable"
            return
        }
        eventsLabel.stringValue = ([sendResult] + provider.animationEventReadout)
            .joined(separator: "\n")
        let snapshot = provider.animationSnapshot
        let state = provider.actorAnimationsEnabled ? "playing" : "bind pose"
        statsLabel.stringValue = "Animation: \(snapshot.playbackCount) playbacks, "
            + "\(snapshot.updatedBoneCount) bones · \(state) · "
            + String(format: "%.2f ms", snapshot.updateMS)
            + " · \(provider.animatedLightCount) animated lights"
    }

    @objc private func lightsChanged() {
        provider?.lightAnimationEnabled = lightsControl.state == .on
        finishInteraction()
    }

    @objc private func eventsChanged() {
        provider?.animationEventsEnabled = eventsControl.state == .on
        refreshOverrideState()
        finishInteraction()
    }

    @objc private func sendEvent() {
        let name = eventField.stringValue
        guard !name.isEmpty, let provider else { return }
        let ran = provider.sendPlayerAnimationEvent(name)
        sendResult = ran ? "Sent: \(name)" : "Sent: \(name) asks for nothing"
        refreshReadout()
        finishInteraction()
    }

    @objc private func enabledChanged() {
        provider?.actorAnimationsEnabled = enabledControl.state == .on
        finishInteraction()
    }
}
