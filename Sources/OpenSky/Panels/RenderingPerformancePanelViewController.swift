// Developer > Rendering Performance: one section per GPU performance feature, each
// with its switch and the numbers that show its effect.

import AppKit
import OpenSkyRendering

final class RenderingPerformancePanelViewController: InspectorPanelViewController {
    let renderTargetsSection = RenderTargetsSection()

    weak var provider: (any RenderPerformanceControlProviding)? {
        didSet {
            renderTargetsSection.provider = provider
        }
    }

    override func makeSections() -> [PanelSectionViewController] {
        [renderTargetsSection]
    }
}
