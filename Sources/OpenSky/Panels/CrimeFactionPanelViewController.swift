// World > Crime & Factions: the sidebar surface for crime and factions. Its
// sections share one picked actor. Order follows a crime: the bounty, the
// theft that raised it, the memberships that decide who cares, and the
// merchants who buy the proceeds.

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
