// World > Environment > Grass live density/distance/wind controls + numeric
// draw/budget inspection. Renderer policy clamps every value again.

import AppKit

extension EnvironmentPanelViewController {
    func makeGrassViews() -> [NSView] {
        grassEnabledControl.target = self
        grassEnabledControl.action = #selector(grassEnabledChanged)
        grassEnabledControl.setAccessibilityIdentifier("GrassEnabledControl")
        configureGrassSlider(
            grassDensityControl,
            action: #selector(grassDensityChanged),
            identifier: "GrassDensityControl"
        )
        configureGrassSlider(
            grassDistanceControl,
            action: #selector(grassDistanceChanged),
            identifier: "GrassDistanceControl"
        )
        configureGrassSlider(
            grassWindControl,
            action: #selector(grassWindChanged),
            identifier: "GrassWindControl"
        )
        return [
            Self.caption("Grass"),
            grassEnabledControl,
            grassRow(grassDensityControl, label: grassDensityLabel),
            grassRow(grassDistanceControl, label: grassDistanceLabel),
            grassRow(grassWindControl, label: grassWindLabel)
        ]
    }

    func syncGrassControls() {
        let available = grassProvider != nil
        for control in [
            grassEnabledControl, grassDensityControl, grassDistanceControl, grassWindControl
        ] {
            control.isEnabled = available
        }
        grassEnabledControl.state = grassProvider?.grassEnabled == true ? .on : .off
        grassDensityControl.floatValue = grassProvider?.grassDensityScale ?? 1
        grassDistanceControl.floatValue = grassProvider?.grassDrawDistance
            ?? GrassRenderPolicy.defaultDrawDistance
        grassWindControl.floatValue = grassProvider?.grassWindScale ?? 1
        updateGrassLabels()
    }

    @objc private func grassEnabledChanged() {
        grassProvider?.grassEnabled = grassEnabledControl.state == .on
        finishGrassInteraction()
    }

    @objc private func grassDensityChanged() {
        grassProvider?.grassDensityScale = grassDensityControl.floatValue
        updateGrassLabels()
        finishGrassSliderInteraction()
    }

    @objc private func grassDistanceChanged() {
        grassProvider?.grassDrawDistance = grassDistanceControl.floatValue
        updateGrassLabels()
        finishGrassSliderInteraction()
    }

    @objc private func grassWindChanged() {
        grassProvider?.grassWindScale = grassWindControl.floatValue
        updateGrassLabels()
        finishGrassSliderInteraction()
    }

    func grassReadout() -> String {
        guard let grassProvider else { return "Grass: unavailable" }
        guard grassProvider.grassEnabled else { return "Grass: disabled" }
        let stats = grassProvider.grassSnapshot
        return "Grass: \(stats.drawnInstances)/\(stats.sceneInstances) drawn in "
            + "\(stats.drawCalls) calls · distance \(stats.distanceCulledInstances), "
            + "density \(stats.densityCulledInstances), frustum "
            + "\(stats.frustumCulledInstances), budget \(stats.budgetDroppedInstances)"
    }

    private func configureGrassSlider(
        _ slider: NSSlider,
        action: Selector,
        identifier: String
    ) {
        slider.target = self
        slider.action = action
        slider.isContinuous = true
        slider.widthAnchor.constraint(equalToConstant: 174).isActive = true
        slider.setAccessibilityIdentifier(identifier)
    }

    private func grassRow(_ slider: NSSlider, label: NSTextField) -> NSStackView {
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.widthAnchor.constraint(equalToConstant: 90).isActive = true
        let row = NSStackView(views: [slider, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func updateGrassLabels() {
        grassDensityLabel.stringValue = String(
            format: "Density %3.0f%%", grassDensityControl.floatValue * 100
        )
        grassDistanceLabel.stringValue = String(
            format: "Distance %.0f", grassDistanceControl.floatValue
        )
        grassWindLabel.stringValue = String(
            format: "Wind %3.0f%%", grassWindControl.floatValue * 100
        )
    }

    private func finishGrassSliderInteraction() {
        refreshStats()
        if NSApp.currentEvent?.type == .leftMouseUp {
            provider?.refocusGameView()
        }
    }

    private func finishGrassInteraction() {
        refreshStats()
        provider?.refocusGameView()
    }
}
