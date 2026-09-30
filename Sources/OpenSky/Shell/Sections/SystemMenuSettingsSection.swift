// World > System Menu > Settings: the data root, read-only here (Settings,
// Cmd+, changes it), and the master volume, which writes through the same audio
// seam as World > Audio so the two cannot disagree.

import AppKit
import OpenSkyMenus

final class SystemMenuSettingsSection: PanelSectionViewController {
    weak var provider: (any SystemMenuControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let volumeControl = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let volumeValueLabel = PanelComponents.valueLabel(width: 44)
    private let dataRootLabel = PanelComponents.statsLabel(
        identifier: "SystemMenuDataRootStatsLabel"
    )
    private let statsLabel = PanelComponents.statsLabel(
        identifier: "SystemMenuSettingsStatsLabel"
    )

    override var sectionTitle: String {
        "Settings"
    }

    override var sectionIdentifier: String {
        "systemMenuSettings"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    static func isOverridden(provider: (any SystemMenuControlProviding)?) -> Bool {
        guard let provider else { return false }
        return provider.systemMenuMasterVolume != 1
    }

    static func resetToDefaults(provider: (any SystemMenuControlProviding)?) {
        provider?.systemMenuMasterVolume = 1
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureSlider(
            volumeControl, target: self, action: #selector(volumeChanged),
            identifier: "SystemMenuMasterVolumeControl", width: 200
        )
        return [
            PanelComponents.group([
                PanelComponents.caption("Game data root"),
                dataRootLabel
            ]),
            PanelComponents.group([
                PanelComponents.caption("Master volume"),
                PanelComponents.sliderRow(
                    slider: volumeControl, valueLabel: volumeValueLabel
                )
            ]),
            PanelComponents.note(
                "Change the data root in Settings (Cmd+,). Per-category volumes land in M9."
            ),
            statsLabel
        ]
    }

    override func syncControls() {
        volumeControl.isEnabled = provider != nil
        volumeControl.floatValue = provider?.systemMenuMasterVolume ?? 1
        volumeValueLabel.stringValue = Self.percentText(volumeControl.floatValue)
    }

    override func refreshReadout() {
        guard let snapshot = provider?.systemMenuSnapshot else {
            dataRootLabel.stringValue = "Data root: unavailable"
            statsLabel.stringValue = "Settings: unavailable"
            return
        }
        dataRootLabel.stringValue = Self.dataRootReadout(for: snapshot)
        statsLabel.stringValue = Self.readout(for: snapshot)
    }

    static func dataRootReadout(for snapshot: SystemMenuControlSnapshot) -> String {
        guard let path = snapshot.dataRootPath else {
            return "Data root: not located"
        }
        let source = snapshot.dataRootSource ?? "unknown"
        return "\(path)\n(source: \(source))"
    }

    static func readout(for snapshot: SystemMenuControlSnapshot) -> String {
        let revealed = snapshot.settingsRevealed ? "revealed" : "not revealed"
        let audio = snapshot.audioEnabled ? "engine on" : "engine off"
        return "Settings row: \(revealed) · audio \(audio)"
    }

    @objc private func volumeChanged() {
        provider?.systemMenuMasterVolume = volumeControl.floatValue
        volumeValueLabel.stringValue = Self.percentText(volumeControl.floatValue)
        finishInteraction(refocusOnMouseUpOnly: true)
    }

    private static func percentText(_ value: Float) -> String {
        String(format: "%3.0f%%", value * 100)
    }
}
