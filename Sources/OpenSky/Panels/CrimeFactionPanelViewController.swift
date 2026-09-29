// World > Crime & Factions destination panel (issue #507, roadmap item 21.8):
// the sidebar verification surface for milestone M21, composed from the
// sections over what items 21.1 through 21.7 built.
//
// A destination of its own rather than more sections under `World > Combat &
// Physics`, where the hostility toggle lives, or `World > Inventory &
// Equipment`, where the raw ownership fields are. Four sections and fifteen
// controls are past the promotion threshold in docs/tools/app-ui.md, the
// sections share an actor picked once, and the M21 acceptance names this path
// top-level, which outranks the threshold anyway. Those two destinations keep
// what they had: the combat toggle is the explicit override this panel's
// reaction line names as its first term, and the raw `XOWN` readout is the
// input the Theft verdict is reached from.
//
// Section order follows what a crime does: the bounty it raises, the theft that
// raised it, the memberships that decide who cares, and the merchants who will
// or will not buy the proceeds.

import AppKit
import OpenSkyCrime

final class CrimeFactionPanelViewController: InspectorPanelViewController {
    let bountySection = CrimeBountySection()
    let theftSection = CrimeTheftSection()
    let membershipSection = FactionMembershipSection()
    let vendorSection = FactionVendorSection()

    weak var provider: (any CrimeFactionControlProviding)? {
        didSet {
            for section in crimeFactionSections {
                section.provider = provider
            }
        }
    }

    /// One ticker for the whole panel: all four sections read the same
    /// snapshot, so it is built once per tick and handed down.
    override var sectionsTickIndependently: Bool {
        false
    }

    override func makeSections() -> [PanelSectionViewController] {
        crimeFactionSections
    }

    /// Builds the tick's snapshot once for all four sections, then clears the
    /// hand-down so a refresh after a button press reads the provider live.
    override func refreshSections() {
        let snapshot = provider?.crimeFactionSnapshot
        for section in crimeFactionSections {
            section.tickSnapshot = snapshot
        }
        defer {
            for section in crimeFactionSections {
                section.tickSnapshot = nil
            }
        }
        super.refreshSections()
    }

    var crimeFactionSections: [CrimeFactionPanelSection] {
        [bountySection, theftSection, membershipSection, vendorSection]
    }
}
