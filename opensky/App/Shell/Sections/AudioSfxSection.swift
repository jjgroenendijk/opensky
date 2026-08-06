// World > Audio > SFX & Ambience section (M9.2.2): the verification surface for
// the world sound director. Independent enable toggles for one-shot SFX and
// the per-cell ambient bed, plus a stop button and a readout showing the most
// recent SFX and the current bed. Same shape as the other audio sections.

import AppKit

final class AudioSfxSection: PanelSectionViewController {
    weak var provider: (any AudioControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let sfxEnabledControl = NSButton(
        checkboxWithTitle: "Door / activator SFX",
        target: nil,
        action: nil
    )
    let ambienceEnabledControl = NSButton(
        checkboxWithTitle: "Per-cell ambience",
        target: nil,
        action: nil
    )
    let stopAmbienceControl = NSButton(title: "Stop ambience", target: nil, action: nil)
    private let statsLabel = PanelComponents.statsLabel(identifier: "AudioSfxStatsLabel")

    override var sectionTitle: String {
        "SFX & Ambience"
    }

    override var sectionIdentifier: String {
        "audioSfx"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    static func isOverridden(provider: (any AudioControlProviding)?) -> Bool {
        guard let provider else { return false }
        // Defaults are both enabled; off on either is an override.
        return !provider.sfxEnabled || !provider.ambienceEnabled
    }

    static func resetToDefaults(provider: (any AudioControlProviding)?) {
        guard let provider else { return }
        provider.sfxEnabled = true
        provider.ambienceEnabled = true
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureCheckbox(
            sfxEnabledControl, target: self, action: #selector(sfxEnabledChanged),
            identifier: "AudioSfxEnabledControl"
        )
        PanelComponents.configureCheckbox(
            ambienceEnabledControl, target: self, action: #selector(ambienceEnabledChanged),
            identifier: "AudioAmbienceEnabledControl"
        )
        PanelComponents.configureButton(
            stopAmbienceControl, target: self, action: #selector(stopAmbience),
            identifier: "AudioStopAmbienceControl"
        )
        return [
            PanelComponents.group([
                sfxEnabledControl,
                ambienceEnabledControl,
                PanelComponents.buttonRow([stopAmbienceControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        let provider = provider
        sfxEnabledControl.isEnabled = provider != nil
        sfxEnabledControl.state = provider?.sfxEnabled == true ? .on : .off
        ambienceEnabledControl.isEnabled = provider != nil
        ambienceEnabledControl.state = provider?.ambienceEnabled == true ? .on : .off
        stopAmbienceControl.isEnabled = provider != nil
    }

    @objc private func sfxEnabledChanged() {
        provider?.sfxEnabled = sfxEnabledControl.state == .on
        finishInteraction()
    }

    @objc private func ambienceEnabledChanged() {
        provider?.ambienceEnabled = ambienceEnabledControl.state == .on
        finishInteraction()
    }

    @objc private func stopAmbience() {
        provider?.stopAmbience()
        finishInteraction()
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "SFX: unavailable"
            return
        }
        var lines = ["SFX: \(provider.lastSFXDescription ?? "none")"]
        if let error = provider.lastSFXError {
            lines.append("SFX error: \(error)")
        }
        lines.append("Ambience: \(provider.currentAmbienceDescription)")
        statsLabel.stringValue = lines.joined(separator: "\n")
    }
}
