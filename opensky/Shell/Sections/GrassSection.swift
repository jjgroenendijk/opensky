// World > Environment > Grass section: live density/distance/wind sliders +
// numeric draw/budget readout (issue #98 decomposition of EnvironmentGrass-
// Controls). Renderer policy clamps every value again.

import AppKit

final class GrassSection: PanelSectionViewController {
    weak var provider: (any GrassControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let enabledControl = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    let densityControl = NSSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    let distanceControl = NSSlider(
        value: Double(GrassRenderPolicy.defaultDrawDistance),
        minValue: Double(GrassRenderPolicy.minimumDrawDistance),
        maxValue: Double(GrassRenderPolicy.maximumDrawDistance),
        target: nil,
        action: nil
    )
    let windControl = NSSlider(
        value: 1,
        minValue: 0,
        maxValue: Double(GrassRenderPolicy.maximumWindScale),
        target: nil,
        action: nil
    )
    private let densityLabel = PanelComponents.valueLabel(width: 90)
    private let distanceLabel = PanelComponents.valueLabel(width: 90)
    private let windLabel = PanelComponents.valueLabel(width: 90)
    private let statsLabel = PanelComponents.statsLabel(identifier: "GrassStatsLabel")

    override var sectionTitle: String {
        "Grass"
    }

    override var sectionIdentifier: String {
        "grass"
    }

    override func makeContentViews() -> [NSView] {
        enabledControl.target = self
        enabledControl.action = #selector(enabledChanged)
        enabledControl.setAccessibilityIdentifier("GrassEnabledControl")
        PanelComponents.configureSlider(
            densityControl, target: self, action: #selector(densityChanged),
            identifier: "GrassDensityControl", width: 174
        )
        PanelComponents.configureSlider(
            distanceControl, target: self, action: #selector(distanceChanged),
            identifier: "GrassDistanceControl", width: 174
        )
        PanelComponents.configureSlider(
            windControl, target: self, action: #selector(windChanged),
            identifier: "GrassWindControl", width: 174
        )
        return [
            enabledControl,
            PanelComponents.sliderRow(slider: densityControl, valueLabel: densityLabel),
            PanelComponents.sliderRow(slider: distanceControl, valueLabel: distanceLabel),
            PanelComponents.sliderRow(slider: windControl, valueLabel: windLabel),
            statsLabel
        ]
    }

    override func syncControls() {
        let available = provider != nil
        for control in [enabledControl, densityControl, distanceControl, windControl] {
            control.isEnabled = available
        }
        enabledControl.state = provider?.grassEnabled == true ? .on : .off
        densityControl.floatValue = provider?.grassDensityScale ?? 1
        distanceControl.floatValue = provider?.grassDrawDistance
            ?? GrassRenderPolicy.defaultDrawDistance
        windControl.floatValue = provider?.grassWindScale ?? 1
        updateLabels()
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Grass: unavailable"
            return
        }
        guard provider.grassEnabled else {
            statsLabel.stringValue = "Grass: disabled"
            return
        }
        let stats = provider.grassSnapshot
        statsLabel.stringValue = "Grass: \(stats.drawnInstances)/\(stats.sceneInstances) drawn in "
            + "\(stats.drawCalls) calls · distance \(stats.distanceCulledInstances), "
            + "density \(stats.densityCulledInstances), frustum "
            + "\(stats.frustumCulledInstances), budget \(stats.budgetDroppedInstances)"
    }

    @objc private func enabledChanged() {
        provider?.grassEnabled = enabledControl.state == .on
        finishInteraction()
    }

    @objc private func densityChanged() {
        provider?.grassDensityScale = densityControl.floatValue
        updateLabels()
        finishInteraction(refocusOnMouseUpOnly: true)
    }

    @objc private func distanceChanged() {
        provider?.grassDrawDistance = distanceControl.floatValue
        updateLabels()
        finishInteraction(refocusOnMouseUpOnly: true)
    }

    @objc private func windChanged() {
        provider?.grassWindScale = windControl.floatValue
        updateLabels()
        finishInteraction(refocusOnMouseUpOnly: true)
    }

    private func updateLabels() {
        densityLabel.stringValue = String(
            format: "Density %3.0f%%",
            densityControl.floatValue * 100
        )
        distanceLabel.stringValue = String(format: "Distance %.0f", distanceControl.floatValue)
        windLabel.stringValue = String(format: "Wind %3.0f%%", windControl.floatValue * 100)
    }
}
