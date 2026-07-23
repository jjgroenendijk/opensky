// World > Environment > Particles section: enable/freeze/emission controls +
// live system readout (issue #98 decomposition of EnvironmentParticleControls).

import AppKit

final class ParticlesSection: PanelSectionViewController {
    weak var provider: (any ParticleControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let enabledControl = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    let frozenControl = NSButton(
        checkboxWithTitle: "Freeze simulation", target: nil, action: nil
    )
    let emissionControl = NSSlider(value: 1, minValue: 0, maxValue: 2, target: nil, action: nil)
    private let emissionLabel = PanelComponents.valueLabel(width: 74)
    private let statsLabel = PanelComponents.statsLabel(identifier: "ParticleStatsLabel")

    override var sectionTitle: String {
        "Particles"
    }

    override var sectionIdentifier: String {
        "particles"
    }

    override func makeContentViews() -> [NSView] {
        enabledControl.target = self
        enabledControl.action = #selector(enabledChanged)
        enabledControl.setAccessibilityIdentifier("ParticlesEnabledControl")
        frozenControl.target = self
        frozenControl.action = #selector(frozenChanged)
        frozenControl.setAccessibilityIdentifier("ParticlesFrozenControl")
        PanelComponents.configureSlider(
            emissionControl,
            target: self,
            action: #selector(emissionChanged),
            identifier: "ParticleEmissionControl",
            width: 190
        )
        return [
            enabledControl,
            frozenControl,
            PanelComponents.sliderRow(slider: emissionControl, valueLabel: emissionLabel),
            statsLabel
        ]
    }

    override func syncControls() {
        let available = provider != nil
        enabledControl.isEnabled = available
        frozenControl.isEnabled = available
        emissionControl.isEnabled = available
        enabledControl.state = provider?.particlesEnabled == true ? .on : .off
        frozenControl.state = provider?.particlesFrozen == true ? .on : .off
        emissionControl.floatValue = provider?.particleEmissionScale ?? 1
        updateEmissionLabel()
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Particles: unavailable"
            return
        }
        let snapshot = provider.particleSnapshot
        let state = provider.particlesEnabled
            ? (provider.particlesFrozen ? "frozen" : "playing") : "disabled"
        statsLabel.stringValue = "Particles: \(snapshot.systemCount) systems, "
            + "\(snapshot.emitterCount) emitters, \(snapshot.liveCount) live · \(state)"
    }

    @objc private func enabledChanged() {
        provider?.particlesEnabled = enabledControl.state == .on
        finishInteraction()
    }

    @objc private func frozenChanged() {
        provider?.particlesFrozen = frozenControl.state == .on
        finishInteraction()
    }

    @objc private func emissionChanged() {
        provider?.particleEmissionScale = emissionControl.floatValue
        updateEmissionLabel()
        finishInteraction(refocusOnMouseUpOnly: true)
    }

    private func updateEmissionLabel() {
        emissionLabel.stringValue = String(format: "Emit %3.0f%%", emissionControl.floatValue * 100)
    }
}
