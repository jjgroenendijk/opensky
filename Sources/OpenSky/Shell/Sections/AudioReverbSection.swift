// World > Audio > Reverb (docs/formats/sound-output-reverb.md): the acoustic
// space's reverb record, the room and wet level it maps to, a wet-level
// override, and the routing of the last one-shot.

import AppKit
import OpenSkyAudio
import OpenSkyWorld

final class AudioReverbSection: PanelSectionViewController {
    weak var provider: (any AudioControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let overrideControl = NSButton(
        checkboxWithTitle: "Override wet level",
        target: nil,
        action: nil
    )
    let wetLevelControl = NSSlider(
        value: 0,
        minValue: Double(ReverbSetting.levelRange.lowerBound),
        maxValue: Double(ReverbSetting.levelRange.upperBound),
        target: nil,
        action: nil
    )
    private let wetLevelLabel = PanelComponents.valueLabel(width: 64)
    private let statsLabel = PanelComponents.statsLabel(identifier: "AudioReverbStatsLabel")

    override var sectionTitle: String {
        "Reverb"
    }

    override var sectionIdentifier: String {
        "audioReverb"
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

    static func isOverridden(provider: (any AudioControlProviding)?) -> Bool {
        provider?.reverbWetOverride != nil
    }

    static func resetToDefaults(provider: (any AudioControlProviding)?) {
        provider?.reverbWetOverride = nil
    }

    override func makeContentViews() -> [NSView] {
        overrideControl.toolTip = "Holds the reverb at the slider's level instead of the room's."
        PanelComponents.configureCheckbox(
            overrideControl, target: self, action: #selector(overrideChanged),
            identifier: "AudioReverbOverrideControl"
        )
        PanelComponents.configureSlider(
            wetLevelControl, target: self, action: #selector(wetLevelChanged),
            identifier: "AudioReverbWetLevelControl", width: PanelMetrics.contentWidth - 72
        )
        return [
            PanelComponents.group([
                overrideControl,
                PanelComponents.sliderRow(slider: wetLevelControl, valueLabel: wetLevelLabel)
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        let wet = provider?.reverbWetOverride
        overrideControl.isEnabled = provider != nil
        overrideControl.state = wet == nil ? .off : .on
        wetLevelControl.isEnabled = wet != nil
        if let wet {
            wetLevelControl.floatValue = wet
        }
        wetLevelLabel.stringValue = String(format: "%.0f dB", wetLevelControl.floatValue)
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Reverb: unavailable"
            return
        }
        let reverb = ReverbReadout.text(
            record: provider.reverbRecord, ramp: provider.audioStatsSnapshot.reverb
        )
        statsLabel.stringValue = reverb + "\nLast routing: \(provider.lastAudioRouting ?? "none")"
    }

    @objc private func overrideChanged() {
        provider?.reverbWetOverride = overrideControl.state == .on ? wetLevelControl
            .floatValue : nil
        syncControls()
        finishInteraction()
    }

    @objc private func wetLevelChanged() {
        if overrideControl.state == .on {
            provider?.reverbWetOverride = wetLevelControl.floatValue
        }
        syncControls()
        finishInteraction()
    }
}
