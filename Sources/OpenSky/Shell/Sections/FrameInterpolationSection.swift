// Developer > Rendering Performance > Frame Interpolation: the switch, the real and shown
// frame rates, and the time from a frame's start to its present.

import AppKit
import OpenSkyRendering

final class FrameInterpolationSection: PanelSectionViewController {
    weak var provider: (any RenderPerformanceControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let enabledControl = NSButton(
        checkboxWithTitle: "Frame interpolation", target: nil, action: nil
    )
    private let statsLabel = PanelComponents.statsLabel(identifier: "FrameInterpolationStatsLabel")

    override var sectionTitle: String {
        "Frame Interpolation"
    }

    override var sectionIdentifier: String {
        "frameInterpolation"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    static func isOverridden(provider: (any RenderPerformanceControlProviding)?) -> Bool {
        provider?.frameInterpolationEnabled ?? false
    }

    static func resetToDefaults(provider: (any RenderPerformanceControlProviding)?) {
        provider?.frameInterpolationEnabled = false
    }

    var statsReadout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        enabledControl.toolTip = "Shows a MetalFX frame between real frames. Adds input lag."
        PanelComponents.configureCheckbox(
            enabledControl, target: self, action: #selector(enabledChanged),
            identifier: "FrameInterpolationControl"
        )
        return [enabledControl, statsLabel]
    }

    override func syncControls() {
        let status = provider?.renderPerformanceSnapshot?.frameInterpolation
        enabledControl.isEnabled = status != nil && status?.unsupportedReason == nil
        enabledControl.state = provider?.frameInterpolationEnabled == true
            && status?.unsupportedReason == nil ? .on : .off
    }

    override func refreshReadout() {
        guard let snapshot = provider?.renderPerformanceSnapshot else {
            statsLabel.stringValue = "Frame interpolation: unavailable"
            return
        }
        statsLabel.stringValue = RenderPerformanceReadout.frameInterpolationText(
            snapshot.frameInterpolation
        )
    }

    @objc private func enabledChanged() {
        provider?.frameInterpolationEnabled = enabledControl.state == .on
        finishInteraction()
    }
}
