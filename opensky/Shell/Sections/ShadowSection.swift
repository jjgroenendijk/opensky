// World > Environment > Sun shadows section (issue #98 decomposition of the
// former monolithic Environment panel). Quality selector bound to the live
// renderer + a 2 Hz shadow-draw readout + the H dev A/B hint.

import AppKit

final class ShadowSection: PanelSectionViewController {
    weak var provider: (any ShadowControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let qualityControl = NSPopUpButton(frame: .zero, pullsDown: false)
    private let statsLabel = PanelComponents.statsLabel(identifier: "ShadowStatsLabel")
    private let qualities = ShadowQuality.allCases

    override var sectionTitle: String {
        "Sun shadows"
    }

    override var sectionIdentifier: String {
        "shadows"
    }

    override func makeContentViews() -> [NSView] {
        for quality in qualities {
            qualityControl.addItem(withTitle: Self.title(for: quality))
        }
        qualityControl.target = self
        qualityControl.action = #selector(qualityChanged)
        qualityControl.setAccessibilityIdentifier("ShadowQualityControl")

        return [
            qualityControl,
            statsLabel,
            PanelComponents.note(
                "Press H in the World view to toggle shadows on/off (dev A/B)."
            )
        ]
    }

    override func syncControls() {
        guard let provider, let idx = qualities.firstIndex(of: provider.shadowQuality) else {
            return
        }
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
