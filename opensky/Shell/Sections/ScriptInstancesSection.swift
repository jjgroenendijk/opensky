// World > Scripts > Instances section (issue #278): how many Papyrus script
// instances the world runtime is holding, and which scripts sit on the
// reference the player is currently looking at.
//
// Purely a readout, so it is never overridden and its reset is a no-op: nothing
// here is a setting a user can leave in a non-default position. The scheduler
// section carries this destination's overridden-ness.

import AppKit

final class ScriptInstancesSection: PanelSectionViewController {
    weak var provider: (any ScriptControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    private let statsLabel = PanelComponents.statsLabel(identifier: "ScriptInstancesStatsLabel")

    override var sectionTitle: String {
        "Instances"
    }

    override var sectionIdentifier: String {
        "scriptInstances"
    }

    /// Current readout text; the verification-surface tests read it directly.
    var readout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        [
            PanelComponents.note(
                "Counts live script instances across every attached cell. The target is the "
                    + "reference under the crosshair, and its script list is what the VM "
                    + "would send an event to."
            ),
            statsLabel
        ]
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Papyrus: unavailable"
            return
        }
        statsLabel.stringValue = ScriptsReadout.instancesText(for: provider.scriptsSnapshot)
    }
}
