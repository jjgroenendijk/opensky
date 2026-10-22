// World > Effects > Impacts & Decals (docs/rendering/decals.md): the impact model,
// decal, and screen blood switches, buttons that show the last impact again at the
// player's feet and splash screen blood, and the counts.

import AppKit
import OpenSkyEffects

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
    let screenBloodControl = NSButton(checkboxWithTitle: "Screen blood", target: nil, action: nil)
    let splashControl = NSButton(title: "Splash blood", target: nil, action: nil)
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
        provider.map { !$0.impactModelsEnabled || !$0.decalsEnabled || !$0.screenBloodEnabled }
            ?? false
    }

    static func resetToDefaults(provider: (any ImpactControlProviding)?) {
        provider?.impactModelsEnabled = true
        provider?.decalsEnabled = true
        provider?.screenBloodEnabled = true
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
        PanelComponents.configureCheckbox(
            screenBloodControl, target: self, action: #selector(togglesChanged),
            identifier: "ScreenBloodControl"
        )
        screenBloodControl.toolTip = "A hit on the player splashes blood on the screen"
        splashControl.toolTip = "Splashes the blood of a 30-point hit, as if the player was struck"
        repeatControl.toolTip = "Shows the last impact again at the player's feet"
        for (button, identifier) in [
            (repeatControl, "ImpactRepeatControl"), (clearControl, "DecalClearControl"),
            (splashControl, "ScreenBloodSplashControl")
        ] {
            PanelComponents.configureButton(
                button, target: self, action: #selector(buttonPressed(_:)), identifier: identifier
            )
        }
        return [
            modelsControl, decalsControl, screenBloodControl,
            PanelComponents.buttonRow([repeatControl, clearControl, splashControl]),
            statsLabel
        ]
    }

    override func syncControls() {
        for control in [
            modelsControl, decalsControl, screenBloodControl, repeatControl, clearControl,
            splashControl
        ] {
            control.isEnabled = provider != nil
        }
        modelsControl.state = provider?.impactModelsEnabled == true ? .on : .off
        decalsControl.state = provider?.decalsEnabled == true ? .on : .off
        screenBloodControl.state = provider?.screenBloodEnabled == true ? .on : .off
    }

    override func refreshReadout() {
        statsLabel.stringValue = provider.map { "\($0.impactSnapshot.text)\n\($0.bloodText)" }
            ?? "Impacts: unavailable"
    }

    @objc private func togglesChanged() {
        provider?.impactModelsEnabled = modelsControl.state == .on
        provider?.decalsEnabled = decalsControl.state == .on
        provider?.screenBloodEnabled = screenBloodControl.state == .on
        finishInteraction()
    }

    @objc private func buttonPressed(_ sender: NSButton) {
        if sender === repeatControl {
            provider?.repeatLastImpact()
        } else if sender === splashControl {
            provider?.splatterScreenBlood(damage: 30)
        } else {
            provider?.clearDecals()
        }
        finishInteraction()
    }
}
