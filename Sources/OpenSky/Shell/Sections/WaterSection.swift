// World > Environment > Water: the depth read toggle and the surface count.

import AppKit
import OpenSkyWorld

final class WaterSection: PanelSectionViewController {
    weak var provider: (any WaterControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let depthControl = NSButton(
        checkboxWithTitle: "See into shallow water", target: nil, action: nil
    )
    private let statsLabel = PanelComponents.statsLabel(identifier: "WaterStatsLabel")

    override var sectionTitle: String {
        "Water"
    }

    override var sectionIdentifier: String {
        "water"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    static func isOverridden(provider: (any WaterControlProviding)?) -> Bool {
        provider?.waterDepthEnabled == false
    }

    static func resetToDefaults(provider: (any WaterControlProviding)?) {
        provider?.waterDepthEnabled = true
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureCheckbox(
            depthControl, target: self, action: #selector(depthChanged),
            identifier: "WaterDepthControl"
        )
        depthControl.toolTip = "Shallow water shows the ground below it"
        return [depthControl, statsLabel]
    }

    override func syncControls() {
        depthControl.isEnabled = provider != nil
        depthControl.state = provider?.waterDepthEnabled == true ? .on : .off
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Water: unavailable"
            return
        }
        statsLabel.stringValue = "Water surfaces: \(provider.waterSurfaceCount)"
    }

    @objc private func depthChanged() {
        provider?.waterDepthEnabled = depthControl.state == .on
        finishInteraction()
    }
}
