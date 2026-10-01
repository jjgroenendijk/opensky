// Shared base for the `World > Progression` sections. A snapshot walks the
// skill's perk tree and runs every `CTDA` condition, so the panel builds it
// once per tick and hands it down through `tickSnapshot`.

import AppKit
import OpenSkyProgression

/// One section of the Progression panel.
class ProgressionPanelSection: PanelSectionViewController {
    /// Weak, for the reason every other panel section holds its provider weakly:
    /// the game controller owns this section's panel, so the section must not
    /// retain back.
    weak var provider: (any ProgressionControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    /// The snapshot the panel built for the tick now running, set by
    /// `ProgressionPanelViewController.refreshSections` for the length of that
    /// fan-out and nil at every other moment.
    var tickSnapshot: ProgressionControlSnapshot?

    /// What a section reads: the panel's snapshot during a tick, a freshly built
    /// one otherwise, and nil when no provider is attached.
    var currentSnapshot: ProgressionControlSnapshot? {
        tickSnapshot ?? provider?.progressionControlSnapshot
    }
}
