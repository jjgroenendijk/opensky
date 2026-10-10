// World > Effects > Impacts & Decals (docs/rendering/decals.md): the impact model
// and decal switches, a button that shows the last impact again at the player's
// feet, and the counts.

import AppKit
import OpenSkyWorld

final class ImpactSection: PanelSectionViewController {
    weak var provider: (any ImpactControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let modelsControl = NSButton(checkboxWithTitle: "Impact effects", target: nil, action: nil)
    let decalsControl = NSButton(checkboxWithTitle: "Decals", target: nil, action: nil)
    let repeatControl = NSButton(title: "Repeat last", target: nil, action: nil)
    let clearControl = NSButton(title: "Clear decals", target: nil, action: nil)
    private let statsLabel = PanelComponents.statsLabel(identifier: "ImpactStatsLabel")

    override var sectionTitle: String {
        "Impacts & Decals"
    }

    override var sectionIdentifier: String {
        "impacts"
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

    static func isOverridden(provider: (any ImpactControlProviding)?) -> Bool {
        provider.map { !$0.impactModelsEnabled || !$0.decalsEnabled } ?? false
    }

    static func resetToDefaults(provider: (any ImpactControlProviding)?) {
        provider?.impactModelsEnabled = true
        provider?.decalsEnabled = true
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureCheckbox(
            modelsControl, target: self, action: #selector(togglesChanged),
            identifier: "ImpactModelsControl"
        )
        modelsControl.toolTip = "Dust under a step, sparks or blood spray where a hit lands"
        PanelComponents.configureCheckbox(
            decalsControl, target: self, action: #selector(togglesChanged),
            identifier: "DecalsControl"
        )
        decalsControl.toolTip = "Marks a hit leaves on the surface, such as blood"
        repeatControl.toolTip = "Shows the last impact again at the player's feet"
        for (button, identifier) in [
            (repeatControl, "ImpactRepeatControl"), (clearControl, "DecalClearControl")
        ] {
            PanelComponents.configureButton(
                button, target: self, action: #selector(buttonPressed(_:)), identifier: identifier
            )
        }
        return [
            modelsControl, decalsControl,
            PanelComponents.buttonRow([repeatControl, clearControl]),
            statsLabel
        ]
    }

    override func syncControls() {
        for control in [modelsControl, decalsControl, repeatControl, clearControl] {
            control.isEnabled = provider != nil
        }
        modelsControl.state = provider?.impactModelsEnabled == true ? .on : .off
        decalsControl.state = provider?.decalsEnabled == true ? .on : .off
    }

    override func refreshReadout() {
        statsLabel.stringValue = provider?.impactSnapshot.text ?? "Impacts: unavailable"
    }

    @objc private func togglesChanged() {
        provider?.impactModelsEnabled = modelsControl.state == .on
        provider?.decalsEnabled = decalsControl.state == .on
        finishInteraction()
    }

    @objc private func buttonPressed(_ sender: NSButton) {
        if sender === repeatControl {
            provider?.repeatLastImpact()
        } else {
            provider?.clearDecals()
        }
        finishInteraction()
    }
}
