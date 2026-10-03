// World > Effects > Visual Effects (docs/rendering/visual-effects.md): pick an
// effect record, read its details, and attach it to the player or the nearest
// actor, above the live effects.

import AppKit
import OpenSkyRendering
import OpenSkyWorld

final class VisualEffectSection: PanelSectionViewController {
    weak var provider: (any VisualEffectControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let nameControl = NSComboBox()
    let attachPlayerControl = NSButton(title: "On player", target: nil, action: nil)
    let attachActorControl = NSButton(title: "On actor", target: nil, action: nil)
    let clearControl = NSButton(title: "Clear", target: nil, action: nil)
    private let detailsLabel = PanelComponents.statsLabel(identifier: "VisualEffectDetailsLabel")
    private let statsLabel = PanelComponents.statsLabel(identifier: "VisualEffectStatsLabel")
    private var names: [String] = []
    private var lastAttach: String?

    override var sectionTitle: String {
        "Visual Effects"
    }

    override var sectionIdentifier: String {
        "visualEffects"
    }

    var readout: String {
        statsLabel.stringValue
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    static func isOverridden(provider: (any VisualEffectControlProviding)?) -> Bool {
        provider?.visualEffectSnapshot.instances.contains { $0.cause == .debug } ?? false
    }

    static func resetToDefaults(provider: (any VisualEffectControlProviding)?) {
        provider?.clearVisualEffects()
    }

    override func makeContentViews() -> [NSView] {
        nameControl.toolTip = "An effect, shader, addon, art, lighting, or material record."
        PanelComponents.configureComboBox(
            nameControl, target: self, action: #selector(nameChanged),
            identifier: "VisualEffectNameControl", width: PanelMetrics.contentWidth
        )
        attachActorControl.toolTip = "Attaches to the nearest actor."
        for (button, identifier) in [
            (attachPlayerControl, "VisualEffectAttachPlayerControl"),
            (attachActorControl, "VisualEffectAttachActorControl"),
            (clearControl, "VisualEffectClearControl")
        ] {
            PanelComponents.configureButton(
                button, target: self, action: #selector(buttonPressed(_:)), identifier: identifier
            )
        }
        return [
            PanelComponents.group([
                nameControl,
                detailsLabel,
                PanelComponents.buttonRow([attachPlayerControl, attachActorControl, clearControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        let current = provider?.visualEffectNames ?? []
        if current != names {
            names = current
            nameControl.removeAllItems()
            nameControl.addItems(withObjectValues: names)
        }
        let hasNames = !names.isEmpty
        nameControl.isEnabled = hasNames
        attachPlayerControl.isEnabled = hasNames
        attachActorControl.isEnabled = hasNames
        clearControl.isEnabled = provider != nil
    }

    override func refreshReadout() {
        syncControls()
        guard let provider else {
            statsLabel.stringValue = "Visual effects: unavailable"
            return
        }
        let details = provider.visualEffectDetails(named: nameControl.stringValue)
        detailsLabel.stringValue = details.isEmpty ? "Record: none" : details
            .joined(separator: "\n")
        let attach = lastAttach.map { "\nAttach: \($0)" } ?? ""
        statsLabel.stringValue = EffectsReadout
            .visualEffects(provider.visualEffectSnapshot) + attach
    }

    @objc private func nameChanged() {
        refreshReadout()
        finishInteraction()
    }

    @objc private func buttonPressed(_ sender: NSButton) {
        let name = nameControl.stringValue
        switch sender {
        case clearControl:
            provider?.clearVisualEffects()
            lastAttach = nil
        default:
            let onActor = sender === attachActorControl
            let attached = provider?
                .attachVisualEffect(named: name, toSelectedActor: onActor) ?? false
            let target = onActor ? "actor" : "player"
            lastAttach = attached ? "\(name) on \(target)" : "\(name) draws nothing there"
        }
        refreshReadout()
        finishInteraction()
    }
}
