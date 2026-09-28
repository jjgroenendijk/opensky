// World > Environment > Sun shadows section (issue #98 decomposition of the
// former monolithic Environment panel). Enable + quality selector bound to the
// live renderer, plus a 2 Hz shadow-draw readout.

import AppKit

final class ShadowSection: PanelSectionViewController {
    weak var provider: (any ShadowControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let enabledControl = NSButton(
        checkboxWithTitle: "Enable sun shadows", target: nil, action: nil
    )
    let qualityControl = NSPopUpButton(frame: .zero, pullsDown: false)
    private let statsLabel = PanelComponents.statsLabel(identifier: "ShadowStatsLabel")
    private let qualities = ShadowQuality.allCases

    override var sectionTitle: String {
        "Sun shadows"
    }

    override var sectionIdentifier: String {
        "shadows"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    static func isOverridden(provider: (any ShadowControlProviding)?) -> Bool {
        guard let provider else { return false }
        return !provider.sunShadowsEnabled
            || provider.shadowQuality != ShadowQualitySettings.fallback
    }

    static func resetToDefaults(provider: (any ShadowControlProviding)?) {
        provider?.sunShadowsEnabled = true
        provider?.shadowQuality = ShadowQualitySettings.fallback
        ShadowQualitySettings.clearOverride()
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureCheckbox(
            enabledControl, target: self, action: #selector(enabledChanged),
            identifier: "SunShadowsEnabledControl"
        )
        for quality in qualities {
            qualityControl.addItem(withTitle: Self.title(for: quality))
        }
        PanelComponents.configurePopUp(
            qualityControl, target: self, action: #selector(qualityChanged),
            identifier: "ShadowQualityControl"
        )
        return [PanelComponents.group([enabledControl, qualityControl]), statsLabel]
    }

    override func syncControls() {
        guard let provider else { return }
        enabledControl.state = provider.sunShadowsEnabled ? .on : .off
        guard let idx = qualities.firstIndex(of: provider.shadowQuality) else { return }
        qualityControl.selectItem(at: idx)
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Shadow stats unavailable."
            return
        }
        let stats = provider.shadowDrawStats
        let state = provider.shadowsActive ? "active" : "idle"
        statsLabel.stringValue = """
        Shadows: \(Self.title(for: provider.shadowQuality)) · \(state)
        Draw calls: \(stats.drawCalls)
        Drawn: \(stats.drawnInstances)  Culled: \(stats.culledInstances)
        Cascades: \(stats.cascadesRendered)
        CPU: \(String(format: "%.2f", provider.shadowUpdateMS)) ms
        """
    }

    @objc private func enabledChanged() {
        provider?.sunShadowsEnabled = enabledControl.state == .on
        finishInteraction()
    }

    @objc private func qualityChanged() {
        let idx = qualityControl.indexOfSelectedItem
        guard qualities.indices.contains(idx) else { return }
        provider?.shadowQuality = qualities[idx]
        finishInteraction()
    }

    private static func title(for quality: ShadowQuality) -> String {
        switch quality {
        case .off: "Off"
        case .low: "Low"
        case .high: "High"
        }
    }
}
