// World > HUD & Interaction > Target: live walk-mode selection diagnostics
// and the exact prompt/marker state published to the vanilla movie.

import AppKit

final class HUDTargetSection: PanelSectionViewController {
    weak var provider: (any HUDControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    private let statsLabel = PanelComponents.statsLabel(identifier: "HUDTargetStatsLabel")

    var statsReadout: String {
        statsLabel.stringValue
    }

    override var sectionTitle: String {
        "Target"
    }

    override var sectionIdentifier: String {
        "hudTarget"
    }

    override func makeContentViews() -> [NSView] {
        [
            PanelComponents.note(
                "Walk mode targets the nearest solid object under the crosshair. "
                    + "The prompt below is the exact text sent to hudmenu.swf."
            ),
            statsLabel
        ]
    }

    override func refreshReadout() {
        guard let snapshot = provider?.hudControlSnapshot else {
            statsLabel.stringValue = "Target: unavailable"
            return
        }
        let target = targetLine(snapshot)
        let prompt = snapshot.prompt ?? "none"
        let markers = snapshot.markerHeadings.isEmpty
            ? "none"
            : snapshot.markerHeadings
            .map { String(format: "%.1f°", $0) }
            .joined(separator: ", ")
        let camera = snapshot.cameraHeading.map {
            String(format: "%.1f°", $0)
        } ?? "unavailable"
        statsLabel.stringValue = """
        \(target)
        Prompt: \(prompt)
        Compass: camera \(camera) · markers \(markers)
        """
    }

    private func targetLine(_ snapshot: HUDControlSnapshot) -> String {
        guard let reference = snapshot.targetReference else {
            return "Target: none"
        }
        let name = snapshot.targetName ?? "unnamed"
        let action = snapshot.targetAction ?? "unknown"
        let distance = snapshot.targetDistance.map {
            String(format: "%.1f units", $0)
        } ?? "unknown distance"
        let base = snapshot.targetBase.map { String(describing: $0) } ?? "unknown"
        let placed = snapshot.targetPosition.map {
            String(format: "(%.1f, %.1f, %.1f)", $0.x, $0.y, $0.z)
        } ?? "unknown"
        let hit = snapshot.hitPosition.map {
            String(format: "(%.1f, %.1f, %.1f)", $0.x, $0.y, $0.z)
        } ?? "unknown"
        return """
        Target: \(reference) · base \(base)
        Action: \(action) \(name) · distance \(distance)
        Placed: \(placed) · hit \(hit)
        """
    }
}
