// Shared base for the three `World > Progression` sections (issue #556): the
// provider they are all written against, and the one snapshot the panel builds
// per tick for them.
//
// ## Why the sections do not read the provider themselves
//
// A progression snapshot is expensive to build — it walks the selected skill's
// perk tree and runs each box's `CTDA` condition run — and all three sections
// read the same one. Left to their own tickers they built it three times per
// tick for one identical reading. So the panel turns
// `sectionsTickIndependently` off, builds the snapshot once, hands it down
// through `tickSnapshot`, and clears it again afterwards: a refresh that happens
// outside a panel tick, which is what a button press does, still reads the
// provider live rather than a value from the last tick.

import AppKit

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
