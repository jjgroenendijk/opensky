// World > Environment > Precipitation section: A/B enable toggle + live runtime
// readout (issue #98 decomposition of EnvironmentPrecipitationControls).

import AppKit

final class PrecipitationSection: PanelSectionViewController {
    weak var provider: (any PrecipitationControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let enabledControl = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let statsLabel = PanelComponents.statsLabel(identifier: "PrecipitationStatsLabel")

    override var sectionTitle: String {
        "Precipitation"
    }

    override var sectionIdentifier: String {
        "precipitation"
    }

    override func makeContentViews() -> [NSView] {
        enabledControl.target = self
        enabledControl.action = #selector(enabledChanged)
        enabledControl.setAccessibilityIdentifier("PrecipitationEnabledControl")
        enabledControl.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return [enabledControl, statsLabel]
    }

    override func syncControls() {
        enabledControl.isEnabled = provider != nil
        enabledControl.state = provider?.precipitationEnabled == true ? .on : .off
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Precipitation: unavailable"
            return
        }
        guard provider.precipitationEnabled else {
            statsLabel.stringValue = "Precipitation: disabled"
            return
        }
        let snapshot = provider.precipitationSnapshot
        let state = snapshot.state
        let kind = if state.rainIntensity > state.snowIntensity {
            "rain"
        } else if state.snowIntensity > 0 {
            "snow"
        } else {
            "clear"
        }
        let roof = snapshot.roofOccluded ? " · roofed" : ""
        let percent = Int((state.intensity * 100).rounded())
        let rain = snapshot.rainLiveCount
        let snow = snapshot.snowLiveCount
        statsLabel.stringValue =
            "Precipitation: \(kind) \(percent)% · rain \(rain), snow \(snow)\(roof)"
    }

    @objc private func enabledChanged() {
        provider?.precipitationEnabled = enabledControl.state == .on
        finishInteraction()
    }
}
