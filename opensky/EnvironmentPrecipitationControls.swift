// World > Environment > Precipitation A/B + live runtime inspection.

import AppKit

extension EnvironmentPanelViewController {
    func makePrecipitationViews() -> [NSView] {
        precipitationEnabledControl.target = self
        precipitationEnabledControl.action = #selector(precipitationEnabledChanged)
        precipitationEnabledControl.setAccessibilityIdentifier("PrecipitationEnabledControl")
        return [Self.caption("Precipitation"), precipitationEnabledControl]
    }

    func syncPrecipitationControls() {
        precipitationEnabledControl.isEnabled = precipitationProvider != nil
        precipitationEnabledControl.state = precipitationProvider?.precipitationEnabled == true
            ? .on : .off
    }

    @objc private func precipitationEnabledChanged() {
        precipitationProvider?.precipitationEnabled = precipitationEnabledControl.state == .on
        refreshStats()
        provider?.refocusGameView()
    }

    func precipitationReadout() -> String {
        guard let precipitationProvider else { return "Precipitation: unavailable" }
        guard precipitationProvider.precipitationEnabled else {
            return "Precipitation: disabled"
        }
        let snapshot = precipitationProvider.precipitationSnapshot
        let state = snapshot.state
        let kind = if state.rainIntensity > state.snowIntensity {
            "rain"
        } else if state.snowIntensity > 0 {
            "snow"
        } else {
            "clear"
        }
        let roof = snapshot.roofOccluded ? " · roofed" : ""
        return "Precipitation: \(kind) \(Int((state.intensity * 100).rounded()))%"
            + " · rain \(snapshot.rainLiveCount), snow \(snapshot.snowLiveCount)\(roof)"
    }
}
