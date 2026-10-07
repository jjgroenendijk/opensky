// Developer > Rendering Performance > GPU Culling: the switch between the CPU and GPU
// culling paths, and how many instances each path drew and culled.

import AppKit
import OpenSkyRendering

final class GPUCullingSection: PanelSectionViewController {
    weak var provider: (any RenderPerformanceControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let enabledControl = NSButton(checkboxWithTitle: "Cull on the GPU", target: nil, action: nil)
    private let statsLabel = PanelComponents.statsLabel(identifier: "GPUCullingStatsLabel")

    override var sectionTitle: String {
        "GPU Culling"
    }

    override var sectionIdentifier: String {
        "gpuCulling"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    static func isOverridden(provider: (any RenderPerformanceControlProviding)?) -> Bool {
        provider?.gpuCullingEnabled == false
    }

    static func resetToDefaults(provider: (any RenderPerformanceControlProviding)?) {
        provider?.gpuCullingEnabled = true
    }

    var statsReadout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        enabledControl.toolTip = "Culls the static scene in a compute pass and draws it indirectly."
        PanelComponents.configureCheckbox(
            enabledControl, target: self, action: #selector(enabledChanged),
            identifier: "GPUCullingEnabledControl"
        )
        return [enabledControl, statsLabel]
    }

    override func syncControls() {
        enabledControl.isEnabled = provider != nil
        enabledControl.state = provider?.gpuCullingEnabled == true ? .on : .off
    }

    override func refreshReadout() {
        guard let snapshot = provider?.renderPerformanceSnapshot else {
            statsLabel.stringValue = "Culling: unavailable"
            return
        }
        statsLabel.stringValue = RenderPerformanceReadout.cullingText(
            cpu: snapshot.cpuCulling, gpu: snapshot.gpuCulling
        )
    }

    @objc private func enabledChanged() {
        provider?.gpuCullingEnabled = enabledControl.state == .on
        finishInteraction()
    }
}
