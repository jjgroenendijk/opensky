// World > Audio > Output section: engine enable, master + provisional category
// volumes, per-category mute and solo (M9.2.4), and the device/format readout
// (M9.1.3). Category names are the provisional M9.1 set (AudioCategory); 9.2.1
// renames them from game data.

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
    private(set) var muteControls: [AudioCategory: NSButton] = [:]
    private(set) var soloControls: [AudioCategory: NSButton] = [:]
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
            || provider.soloedAudioCategory != nil
            || AudioCategory.allCases.contains {
                provider.audioVolume(for: $0) != 1 || provider.audioCategoryIsMuted($0)
            }
    }

    static func resetToDefaults(provider: (any AudioControlProviding)?) {
        guard let provider else { return }
        provider.audioEnabled = false
        provider.audioMasterVolume = 1
        provider.soloedAudioCategory = nil
        for category in AudioCategory.allCases {
            provider.setAudioVolume(1, for: category)
            provider.setAudioCategoryMuted(false, for: category)
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
        let volumeRows: [NSView] = [
            PanelComponents.caption("Master"),
            PanelComponents.sliderRow(slider: masterControl, valueLabel: masterValueLabel)
        ] + AudioCategory.allCases.flatMap(makeCategoryRows(for:))
        return [
            PanelComponents.group([enabledControl]),
            PanelComponents.group(volumeRows),
            statsLabel
        ]
    }

    /// Caption, volume slider, and the mute/solo pair for one category. Solo is
    /// a checkbox rather than a radio group because clicking the active one
    /// clears it, which a radio group cannot express.
    private func makeCategoryRows(for category: AudioCategory) -> [NSView] {
        let slider = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
        PanelComponents.configureSlider(
            slider, target: self, action: #selector(categoryChanged(_:)),
            identifier: "Audio\(category.identifierFragment)VolumeControl", width: 200
        )
        let valueLabel = PanelComponents.valueLabel(width: 44)
        let mute = NSButton(checkboxWithTitle: "Mute", target: nil, action: nil)
        PanelComponents.configureCheckbox(
            mute, target: self, action: #selector(muteChanged(_:)),
            identifier: "Audio\(category.identifierFragment)MuteControl"
        )
        let solo = NSButton(checkboxWithTitle: "Solo", target: nil, action: nil)
        PanelComponents.configureCheckbox(
            solo, target: self, action: #selector(soloChanged(_:)),
            identifier: "Audio\(category.identifierFragment)SoloControl"
        )
        categoryControls[category] = slider
        categoryValueLabels[category] = valueLabel
        muteControls[category] = mute
        soloControls[category] = solo
        return [
            PanelComponents.caption(category.displayName),
            PanelComponents.sliderRow(slider: slider, valueLabel: valueLabel),
            PanelComponents.buttonRow([mute, solo])
        ]
    }

    override func syncControls() {
        let provider = provider
        enabledControl.isEnabled = provider != nil
        enabledControl.state = provider?.audioEnabled == true ? .on : .off
        masterControl.isEnabled = provider != nil
        masterControl.floatValue = provider?.audioMasterVolume ?? 1
        let soloed = provider?.soloedAudioCategory
        for (category, slider) in categoryControls {
            slider.isEnabled = provider != nil
            slider.floatValue = provider?.audioVolume(for: category) ?? 1
            let mute = muteControls[category]
            mute?.isEnabled = provider != nil
            mute?.state = provider?.audioCategoryIsMuted(category) == true ? .on : .off
            let solo = soloControls[category]
            solo?.isEnabled = provider != nil
            solo?.state = soloed == category ? .on : .off
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

    @objc private func muteChanged(_ sender: NSButton) {
        for (category, control) in muteControls where control === sender {
            provider?.setAudioCategoryMuted(sender.state == .on, for: category)
        }
        refreshReadout()
        finishInteraction()
    }

    /// Solo is mutually exclusive: picking one category clears any other, and
    /// clicking the category that is already soloed clears solo entirely.
    @objc private func soloChanged(_ sender: NSButton) {
        for (category, control) in soloControls where control === sender {
            provider?.soloedAudioCategory = sender.state == .on ? category : nil
        }
        let soloed = provider?.soloedAudioCategory
        for (category, control) in soloControls {
            control.state = soloed == category ? .on : .off
        }
        refreshReadout()
        finishInteraction()
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Audio: unavailable"
            return
        }
        let snapshot = provider.audioStatsSnapshot
        var lines: [String] = if snapshot.enabled {
            [
                "Audio: \(snapshot.engineRunning ? "running" : "not running")",
                "Output: \(snapshot.outputDescription)"
            ]
        } else {
            ["Audio: disabled"]
        }
        lines.append(Self.routingLine(provider: provider))
        statsLabel.stringValue = lines.joined(separator: "\n")
    }

    /// Mute and solo state as one readout line, so the acceptance record can
    /// read the category routing out of the panel text.
    private static func routingLine(provider: any AudioControlProviding) -> String {
        let muted = AudioCategory.allCases
            .filter { provider.audioCategoryIsMuted($0) }
            .map(\.displayName)
        let mutedText = muted.isEmpty ? "none" : muted.joined(separator: ", ")
        let soloText = provider.soloedAudioCategory?.displayName ?? "none"
        return "Mute: \(mutedText)  Solo: \(soloText)"
    }

    private static func percentText(_ value: Float) -> String {
        String(format: "%3.0f%%", value * 100)
    }
}
