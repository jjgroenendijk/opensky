// World > Scene section: what the frame actually drew and what the streamer is
// holding resident, so a slow frame can be read against its cause without a
// CLI command.

import AppKit

final class SceneStatsSection: PanelSectionViewController {
    weak var provider: (any SceneStatsProviding)? {
        didSet {
            guard isViewLoaded else { return }
            refreshReadout()
        }
    }

    private let statsLabel = PanelComponents.statsLabel(identifier: "SceneStatsLabel")

    override var sectionTitle: String {
        "Scene"
    }

    override var sectionIdentifier: String {
        "scene"
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
            statsLabel.stringValue = "Scene: unavailable"
            return
        }
        let snapshot = provider.sceneStatsSnapshot
        // nil only when the mach footprint call fails; report that rather than
        // inventing a zero.
        let memory = snapshot.memoryFootprintMB.map { String(format: "%.0f MB", $0) } ?? "n/a"
        statsLabel.stringValue = """
        Draw calls: \(snapshot.drawCalls)
        Drawn: \(snapshot.drawnInstances)  Culled: \(snapshot.culledInstances)
        Resident cells: \(snapshot.residentCellCount)
        Memory: \(memory)
        """
    }
}
