// World > World Load section: how long each stage of the world data load took
// for the running session, slowest first.

import AppKit
import OpenSkyWorld

final class WorldLoadSection: PanelSectionViewController {
    weak var provider: (any WorldLoadReportProviding)? {
        didSet {
            guard isViewLoaded else { return }
            refreshReadout()
        }
    }

    private let statsLabel = PanelComponents.statsLabel(identifier: "WorldLoadStatsLabel")

    override var sectionTitle: String {
        "World Load"
    }

    override var sectionIdentifier: String {
        "worldLoad"
    }

    var statsReadout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        statsLabel.toolTip = "Time of each world data stage when this session started"
        return [statsLabel]
    }

    override func refreshReadout() {
        guard let report = provider?.worldLoadReport else {
            statsLabel.stringValue = "World load: none"
            return
        }
        // Stages overlap, so the total is the wall time, not the sum of the lines.
        let lines = report.timeline.slowestFirst.map {
            "\($0.stage.title): \($0.duration.secondsText)"
        }
        statsLabel.stringValue = (["Total: \(report.total.secondsText)"] + lines)
            .joined(separator: "\n")
    }
}
