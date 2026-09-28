// Shared base for the four `World > Crime & Factions` sections (issue #507):
// the provider they are written against, the snapshot the panel builds once per
// tick for all of them, and the faction popup they each fill.
//
// The snapshot is handed down for the reason `ProgressionPanelSection` hands its
// own down: every section reads the same value, and building it resolves both
// actors' memberships and runs the hostility derivation, so four independent
// tickers would build it four times for one identical reading.

import AppKit
import OpenSkyCrime
import OpenSkyEngine
import OpenSkyFormatsESM

/// One section of the Crime & Factions panel.
class CrimeFactionPanelSection: PanelSectionViewController {
    /// Weak: the game controller owns this section's panel, so the section must
    /// not retain back.
    weak var provider: (any CrimeFactionControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    /// The snapshot the panel built for the tick now running, nil otherwise.
    var tickSnapshot: CrimeFactionControlSnapshot?

    /// What a section reads: the panel's snapshot during a tick, a freshly
    /// built one otherwise, and nil with no provider attached.
    var currentSnapshot: CrimeFactionControlSnapshot? {
        tickSnapshot ?? provider?.crimeFactionSnapshot
    }

    /// Fills `popUp` with `options` behind `leading` fixed rows, rebuilding only
    /// when the list changed — the readout ticks at 2 Hz, and rebuilding a popup
    /// under an open menu would close it in the user's hand — and selects
    /// `selected`, or the first leading row when it is nil.
    ///
    /// - Returns: the options now behind the popup's rows after the leading ones.
    func sync(
        _ popUp: NSPopUpButton,
        options: [FactionOption],
        shown: [FactionOption],
        leading: [String] = [],
        selected: ReferenceKey?
    ) -> [FactionOption] {
        popUp.isEnabled = !options.isEmpty
        if options != shown || popUp.numberOfItems != leading.count + options.count {
            popUp.removeAllItems()
            popUp.addItems(withTitles: leading + options.map(\.name))
        }
        if let selected, let index = options.firstIndex(where: { $0.key == selected }) {
            popUp.selectItem(at: leading.count + index)
        } else if !leading.isEmpty {
            popUp.selectItem(at: 0)
        }
        return options
    }

    /// The option the popup's selected row stands for, or nil for a leading row.
    func selectedOption(
        of popUp: NSPopUpButton,
        in options: [FactionOption],
        leading: Int = 0
    ) -> FactionOption? {
        let index = popUp.indexOfSelectedItem - leading
        return options.indices.contains(index) ? options[index] : nil
    }
}
