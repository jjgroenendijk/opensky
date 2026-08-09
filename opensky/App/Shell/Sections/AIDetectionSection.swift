// World > AI & Navigation > Detection section (issue #202, roadmap item 16.6;
// shipped by the M16 gate, issue #203): what the perception pass tracked this
// step, every pair the selected actor is on either side of, and where each
// detection constant came from.
//
// Read-only, and deliberately so. Detection level accumulates from distance,
// light, sound and line of sight on a fixed step; a control that set a level
// directly would be showing a number the formula never produced, and the way to
// make an actor notice you is to walk into its cone. The overlay checkbox that
// draws those cones is the one control this needs, and it lives in the Overlays
// section beside the other two rather than being duplicated here.
//
// Two providers rather than one: the pass itself, and the selection every
// section under this destination answers for.

import AppKit

final class AIDetectionSection: PanelSectionViewController {
    weak var provider: (any PerceptionControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            refreshReadout()
        }
    }

    weak var selectionProvider: (any AINavigationControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            refreshReadout()
        }
    }

    private let statsLabel = PanelComponents.statsLabel(identifier: "DetectionStatsLabel")
    private let settingsLabel = PanelComponents.statsLabel(
        identifier: "DetectionSettingsStatsLabel"
    )

    override var sectionTitle: String {
        "Detection"
    }

    override var sectionIdentifier: String {
        "aiDetection"
    }

    var readout: String {
        statsLabel.stringValue
    }

    var settingsReadout: String {
        settingsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        [
            PanelComponents.note(
                "Each observer accumulates awareness of each target from distance, the "
                    + "target's light level, the noise its gait makes, and whether anything "
                    + "solid is in the way. The line below is one per tracked pair the "
                    + "selected actor is part of. Switch on the detection overlay above to "
                    + "see the cones the same numbers come from. Every constant is resolved "
                    + "from a game setting, and the second block says which plugin won."
            ),
            statsLabel,
            settingsLabel
        ]
    }

    override func refreshReadout() {
        guard let snapshot = provider?.perceptionSnapshot, !snapshot.isUnavailable else {
            statsLabel.stringValue = "Detection: unavailable"
            settingsLabel.stringValue = ""
            return
        }
        let selection = selectionProvider?.aiNavigationSnapshot ?? .unavailable
        let lines = selection.selectedActor.map { provider?.perceptionLines(for: $0) ?? [] } ?? []
        statsLabel.stringValue = [
            AIDetectionReadout.passText(for: snapshot),
            AIDetectionReadout.pairsText(lines: lines, actor: selection.selectedActorName)
        ].joined(separator: "\n")
        settingsLabel.stringValue = Self.settingsText(for: snapshot)
    }

    /// Every resolved detection constant beside the plugin, fallback, or
    /// OpenSky constant it came from — the provenance 16.6 published so a number
    /// in the formula is never unattributed.
    nonisolated static func settingsText(for snapshot: PerceptionControlSnapshot) -> String {
        let rows = snapshot.settings.map { setting in
            String(format: "  %@ = %.3f [%@]", setting.editorID, setting.value, setting.source)
        }
        return (["Settings: \(rows.count) resolved"] + rows).joined(separator: "\n")
    }
}
