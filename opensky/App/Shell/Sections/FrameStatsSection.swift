// World > Frame section: the live frame-timing readout. Reads the same closed
// short window `FrameStats` publishes for every other consumer, so two surfaces
// can never quote different numbers for the same frame.

import AppKit

final class FrameStatsSection: PanelSectionViewController {
    weak var provider: (any FrameStatsProviding)? {
        didSet {
            guard isViewLoaded else { return }
            refreshReadout()
        }
    }

    private let statsLabel = PanelComponents.statsLabel(identifier: "FrameStatsLabel")

    override var sectionTitle: String {
        "Frame"
    }

    override var sectionIdentifier: String {
        "frame"
    }

    /// Current readout text; the verification-surface tests read it directly.
    var statsReadout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        [statsLabel]
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Frame: unavailable"
            return
        }
        let snapshot = provider.frameStatsSnapshot
        // Before the first window closes there is no reading at all; showing
        // the zeroed snapshot would read as a stalled renderer.
        guard snapshot.hasMeasurement else {
            statsLabel.stringValue = "Frame: measuring"
            return
        }
        let gpu = snapshot.gpuMS.map { String(format: "%.2f ms", $0) } ?? "n/a"
        statsLabel.stringValue = String(
            format: """
            FPS: %.0f  Frame: %.2f ms
            Worst: %.2f ms
            CPU encode: %.2f ms
            GPU: %@
            """,
            snapshot.fps, snapshot.frameMS, snapshot.maxFrameMS, snapshot.encodeMS, gpu
        )
    }
}
