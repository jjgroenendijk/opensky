// Developer > Rendering Performance > Ray-Traced Shadows: the switch, a view of the
// traced shadow alone, and why the GPU cannot run it when it cannot.

import AppKit
import OpenSkyRendering

final class RayTracedShadowsSection: PanelSectionViewController {
    weak var provider: (any RenderPerformanceControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let enabledControl = NSButton(
        checkboxWithTitle: "Ray-traced sun shadows", target: nil, action: nil
    )
    let viewControl = NSButton(checkboxWithTitle: "Show only the shadows", target: nil, action: nil)
    private let statsLabel = PanelComponents.statsLabel(identifier: "RayTracedShadowsStatsLabel")

    override var sectionTitle: String {
        "Ray-Traced Shadows"
    }

    override var sectionIdentifier: String {
        "rayTracedShadows"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    static func isOverridden(provider: (any RenderPerformanceControlProviding)?) -> Bool {
        guard let provider else { return false }
        return provider.rayTracedShadowsEnabled || provider.rayTracedShadowView
    }

    static func resetToDefaults(provider: (any RenderPerformanceControlProviding)?) {
        provider?.rayTracedShadowsEnabled = false
        provider?.rayTracedShadowView = false
    }

    var statsReadout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        enabledControl.toolTip = "Traces one ray to the sun per pixel. Needs an M3 or later GPU."
        PanelComponents.configureCheckbox(
            enabledControl, target: self, action: #selector(enabledChanged),
            identifier: "RayTracedShadowsEnabledControl"
        )
        viewControl.toolTip = "Draws the traced shadow alone: white is lit, black is shadowed."
        PanelComponents.configureCheckbox(
            viewControl, target: self, action: #selector(viewChanged),
            identifier: "RayTracedShadowsViewControl"
        )
        return [enabledControl, viewControl, statsLabel]
    }

    override func syncControls() {
        let available = provider?.renderPerformanceSnapshot?.rayTracing.isAvailable == true
        enabledControl.isEnabled = available
        viewControl.isEnabled = available && provider?.rayTracedShadowsEnabled == true
        enabledControl.state = provider?.rayTracedShadowsEnabled == true ? .on : .off
        viewControl.state = provider?.rayTracedShadowView == true ? .on : .off
    }

    override func refreshReadout() {
        guard let snapshot = provider?.renderPerformanceSnapshot else {
            statsLabel.stringValue = "Ray tracing: unavailable"
            return
        }
        statsLabel.stringValue = RenderPerformanceReadout.rayTracedShadowText(
            snapshot.rayTracing, stats: snapshot.rayTracedShadows
        )
    }

    @objc private func enabledChanged() {
        provider?.rayTracedShadowsEnabled = enabledControl.state == .on
        syncControls()
        finishInteraction()
    }

    @objc private func viewChanged() {
        provider?.rayTracedShadowView = viewControl.state == .on
        finishInteraction()
    }
}
