// Developer > Rendering Performance > Render Targets: the GPU memory each render
// target costs. A memoryless target lives in tile memory and costs none.

import AppKit
import OpenSkyRendering

final class RenderTargetsSection: PanelSectionViewController {
    weak var provider: (any RenderPerformanceControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            refreshReadout()
        }
    }

    private let statsLabel = PanelComponents.statsLabel(identifier: "RenderTargetsStatsLabel")

    override var sectionTitle: String {
        "Render Targets"
    }

    override var sectionIdentifier: String {
        "renderTargets"
    }

    var statsReadout: String {
        statsLabel.stringValue
    }

    var statsLabelIdentifier: String? {
        statsLabel.accessibilityIdentifier()
    }

    override func makeContentViews() -> [NSView] {
        statsLabel.toolTip = "GPU memory of the shadow maps, scene depth, and grade targets."
        return [statsLabel]
    }

    override func refreshReadout() {
        guard let snapshot = provider?.renderPerformanceSnapshot else {
            statsLabel.stringValue = "Render targets: unavailable"
            return
        }
        statsLabel.stringValue = RenderPerformanceReadout.renderTargetText(snapshot.renderTargets)
    }
}
