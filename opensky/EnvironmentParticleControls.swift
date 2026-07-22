// World > Environment > Particles control construction + actions, split from
// the shared environment panel for file limits.

import AppKit

extension EnvironmentPanelViewController {
    func makeParticleViews() -> [NSView] {
        particlesEnabledControl.target = self
        particlesEnabledControl.action = #selector(particlesEnabledChanged)
        particlesEnabledControl.setAccessibilityIdentifier("ParticlesEnabledControl")
        particlesFrozenControl.target = self
        particlesFrozenControl.action = #selector(particlesFrozenChanged)
        particlesFrozenControl.setAccessibilityIdentifier("ParticlesFrozenControl")
        emissionControl.target = self
        emissionControl.action = #selector(particleEmissionChanged)
        emissionControl.isContinuous = true
        emissionControl.widthAnchor.constraint(equalToConstant: 190).isActive = true
        emissionControl.setAccessibilityIdentifier("ParticleEmissionControl")
        emissionLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        emissionLabel.widthAnchor.constraint(equalToConstant: 74).isActive = true
        let emissionRow = NSStackView(views: [emissionControl, emissionLabel])
        emissionRow.orientation = .horizontal
        emissionRow.alignment = .centerY
        return [
            Self.caption("Particles"),
            particlesEnabledControl,
            particlesFrozenControl,
            emissionRow
        ]
    }

    func syncParticleControls() {
        let available = particleProvider != nil
        particlesEnabledControl.isEnabled = available
        particlesFrozenControl.isEnabled = available
        emissionControl.isEnabled = available
        particlesEnabledControl.state = particleProvider?.particlesEnabled == true ? .on : .off
        particlesFrozenControl.state = particleProvider?.particlesFrozen == true ? .on : .off
        emissionControl.floatValue = particleProvider?.particleEmissionScale ?? 1
        emissionLabel.stringValue = String(
            format: "Emit %3.0f%%", emissionControl.floatValue * 100
        )
    }

    @objc private func particlesEnabledChanged() {
        particleProvider?.particlesEnabled = particlesEnabledControl.state == .on
        refreshStats()
        provider?.refocusGameView()
    }

    @objc private func particlesFrozenChanged() {
        particleProvider?.particlesFrozen = particlesFrozenControl.state == .on
        refreshStats()
        provider?.refocusGameView()
    }

    @objc private func particleEmissionChanged() {
        particleProvider?.particleEmissionScale = emissionControl.floatValue
        emissionLabel.stringValue = String(
            format: "Emit %3.0f%%", emissionControl.floatValue * 100
        )
        if NSApp.currentEvent?.type == .leftMouseUp {
            provider?.refocusGameView()
        }
    }

    func particleReadout() -> String {
        guard let particleProvider else { return "Particles: unavailable" }
        let snapshot = particleProvider.particleSnapshot
        let state = particleProvider.particlesEnabled
            ? (particleProvider.particlesFrozen ? "frozen" : "playing") : "disabled"
        return "Particles: \(snapshot.systemCount) systems, \(snapshot.emitterCount) emitters, "
            + "\(snapshot.liveCount) live · \(state)"
    }
}
