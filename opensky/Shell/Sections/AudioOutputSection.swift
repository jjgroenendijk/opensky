// World > Audio > Output section: engine enable, master + provisional category
// volumes, and the device/format readout (M9.1.3). Category names are the
// provisional M9.1 set (AudioCategory); 9.2.1 renames them from game data.

import AppKit

final class AudioOutputSection: PanelSectionViewController {
    weak var provider: (any AudioControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let enabledControl = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    let masterControl = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let masterValueLabel = PanelComponents.valueLabel(width: 44)
    private(set) var categoryControls: [AudioCategory: NSSlider] = [:]
    private var categoryValueLabels: [AudioCategory: NSTextField] = [:]
    private let statsLabel = PanelComponents.statsLabel(identifier: "AudioStatsLabel")

    override var sectionTitle: String {
        "Output"
    }

    override var sectionIdentifier: String {
        "audioOutput"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    static func isOverridden(provider: (any AudioControlProviding)?) -> Bool {
        guard let provider else { return false }
        return provider.audioEnabled
            || provider.audioMasterVolume != 1
            || AudioCategory.allCases.contains {
                provider.audioVolume(for: $0) != 1
            }
    }

    static func resetToDefaults(provider: (any AudioControlProviding)?) {
        guard let provider else { return }
        provider.audioEnabled = false
        provider.audioMasterVolume = 1
        for category in AudioCategory.allCases {
            provider.setAudioVolume(1, for: category)
        }
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureCheckbox(
            enabledControl, target: self, action: #selector(enabledChanged),
            identifier: "AudioEnabledControl"
        )
        PanelComponents.configureSlider(
            masterControl, target: self, action: #selector(masterChanged),
            identifier: "AudioMasterVolumeControl", width: 200
        )
        var volumeRows: [NSView] = [
            PanelComponents.caption("Master"),
            PanelComponents.sliderRow(slider: masterControl, valueLabel: masterValueLabel)
        ]
        for category in AudioCategory.allCases {
            let slider = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
            PanelComponents.configureSlider(
                slider, target: self, action: #selector(categoryChanged(_:)),
                identifier: "Audio\(category.identifierFragment)VolumeControl", width: 200
            )
            let valueLabel = PanelComponents.valueLabel(width: 44)
            categoryControls[category] = slider
            categoryValueLabels[category] = valueLabel
            volumeRows.append(PanelComponents.caption(category.displayName))
            volumeRows.append(
                PanelComponents.sliderRow(slider: slider, valueLabel: valueLabel)
            )
        }
        return [
            PanelComponents.group([enabledControl]),
            PanelComponents.group(volumeRows),
            statsLabel
        ]
    }

    override func syncControls() {
        let provider = provider
        enabledControl.isEnabled = provider != nil
        enabledControl.state = provider?.audioEnabled == true ? .on : .off
        masterControl.isEnabled = provider != nil
        masterControl.floatValue = provider?.audioMasterVolume ?? 1
        for (category, slider) in categoryControls {
            slider.isEnabled = provider != nil
            slider.floatValue = provider?.audioVolume(for: category) ?? 1
        }
        syncValueLabels()
    }

    private func syncValueLabels() {
        masterValueLabel.stringValue = Self.percentText(masterControl.floatValue)
        for (category, slider) in categoryControls {
            categoryValueLabels[category]?.stringValue = Self.percentText(slider.floatValue)
        }
    }

    @objc private func enabledChanged() {
        provider?.audioEnabled = enabledControl.state == .on
        finishInteraction()
    }

    @objc private func masterChanged() {
        provider?.audioMasterVolume = masterControl.floatValue
        syncValueLabels()
        finishInteraction(refocusOnMouseUpOnly: true)
    }

    @objc private func categoryChanged(_ sender: NSSlider) {
        for (category, slider) in categoryControls where slider === sender {
            provider?.setAudioVolume(sender.floatValue, for: category)
        }
        syncValueLabels()
        finishInteraction(refocusOnMouseUpOnly: true)
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Audio: unavailable"
            return
        }
        let snapshot = provider.audioStatsSnapshot
        guard snapshot.enabled else {
            statsLabel.stringValue = "Audio: disabled"
            return
        }
        let state = snapshot.engineRunning ? "running" : "not running"
        statsLabel.stringValue = """
        Audio: \(state)
        Output: \(snapshot.outputDescription)
        """
    }

    private static func percentText(_ value: Float) -> String {
        String(format: "%3.0f%%", value * 100)
    }
}
