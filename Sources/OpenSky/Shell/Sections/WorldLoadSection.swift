// World > World Load section: how long each stage of the world data load took
// for the running session, slowest first, then each phase of the session start.

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
        statsLabel.toolTip = "Time of each world data stage and session start phase"
        return [statsLabel]
    }

    override func refreshReadout() {
        guard let provider, let report = provider.worldLoadReport else {
            statsLabel.stringValue = "World load: none"
            return
        }
        // Stages overlap, so the total is the wall time, not the sum of the lines.
        let lines = report.timeline.slowestFirst.map {
            "\($0.stage.title): \($0.duration.secondsText)"
        }
        statsLabel.stringValue = (["Total: \(report.total.secondsText)"] + lines
            + Self.sessionStartLines(provider.sessionStartTiming))
            .joined(separator: "\n")
    }

    /// The phases after the load, in run order, so a slow first frame shows on its own line.
    private static func sessionStartLines(_ timing: SessionStartTiming) -> [String] {
        guard !timing.measured.isEmpty else { return [] }
        return ["Session start: \(timing.total.secondsText)"] + timing.measured.map {
            "\($0.phase.title): \($0.duration.secondsText)"
        }
    }
}
