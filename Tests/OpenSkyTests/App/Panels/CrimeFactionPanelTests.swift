// The World > Crime & Factions panel: its
// placement, its accessibility-id contract, and that each control sends what
// its field, checkbox and popup hold.
//
// Built through the registry factory the app itself uses, over the recording
// fake, so what is under test is the destination a user clicks.

import AppKit
@testable import OpenSky
@testable import OpenSkyCrime
import OpenSkyCrimeTesting
@testable import OpenSkyFormatsESM
import Testing

@MainActor
struct CrimeFactionPanelTests {
    static func panel(
        providers: FakeWorldProviders
    ) throws -> CrimeFactionPanelViewController {
        let descriptor = try #require(DestinationRegistry.destination(id: "crimeFactions"))
        guard case let .worldInspector(makePanel) = descriptor.content else {
            throw ProgressionPanelError.notAWorldInspector
        }
        let panel = try #require(
            makePanel(WorldPanelContext(providers: providers))
                as? CrimeFactionPanelViewController
        )
        panel.loadViewIfNeeded()
        return panel
    }

    @Test
    func descriptorPlacementIsPinned() throws {
        let descriptor = try #require(DestinationRegistry.destination(id: "crimeFactions"))
        #expect(descriptor.sidebarIdentifier == "Destination-crimeFactions")
        #expect(descriptor.title == "Crime & Factions")
        #expect(descriptor.section == .world)
        #expect(descriptor.symbolName == "building.columns")
        #expect(descriptor.overrides != nil)
        let ids = DestinationRegistry.all.map(\.id)
        let index = try #require(ids.firstIndex(of: "crimeFactions"))
        #expect(ids[index - 1] == "progression")
        #expect(ids[index + 1] == "systemMenu")
    }

    @Test
    func theSectionsAndControlsCarryTheirIdentifiers() throws {
        let panel = try Self.panel(providers: FakeWorldProviders())
        #expect(panel.crimeFactionSections.map(\.sectionIdentifier) == [
            "crimeBounty", "crimeTheft", "factionMembership", "factionVendor"
        ])
        let bounty = panel.bountySection
        let members = panel.membershipSection
        let vendor = panel.vendorSection
        let controls: [(NSView, String)] = [
            (bounty.factionControl, "CrimeBountyFactionControl"),
            (bounty.amountControl, "CrimeBountyAmountControl"),
            (bounty.violentControl, "CrimeBountyViolentControl"),
            (bounty.addControl, "CrimeBountyAddControl"),
            (bounty.clearControl, "CrimeBountyClearControl"),
            (bounty.guardCheckControl, "CrimeGuardCheckControl"),
            (bounty.resistControl, "CrimeResistArrestControl"),
            (members.crosshairControl, "FactionSubjectCrosshairControl"),
            (members.playerControl, "FactionSubjectPlayerControl"),
            (members.factionControl, "FactionSelectControl"),
            (members.rankControl, "FactionRankControl"),
            (members.joinControl, "FactionJoinControl"),
            (members.leaveControl, "FactionLeaveControl"),
            (vendor.overrideControl, "FactionVendorOverrideControl"),
            (vendor.barterControl, "FactionBarterControl")
        ]
        for (control, identifier) in controls {
            #expect(control.accessibilityIdentifier() == identifier)
        }
        for label in [
            "CrimeBountyStatsLabel", "CrimeTheftStatsLabel",
            "FactionMembershipStatsLabel", "FactionVendorStatsLabel"
        ] {
            #expect(scriptsReadout(label, in: panel.view) != nil, "\(label) is missing")
        }
    }

    @Test
    func withNoRuntimeThePanelSaysSo() throws {
        // Held here: the panel keeps its provider weakly.
        let providers = FakeWorldProviders()
        let panel = try Self.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }
        #expect(panel.bountySection.readout.contains("no game data loaded"))
        #expect(!panel.bountySection.addControl.isEnabled)
    }

    @Test
    func theReadoutsCarryTheSnapshot() throws {
        let providers = FakeWorldProviders()
        providers.crimeFactions.snapshot = CrimeFactionSnapshotFixture.snapshot()
        let panel = try Self.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        #expect(panel.bountySection.readout.contains("Bounty: 1040 gold with 1 faction(s)"))
        #expect(panel.bountySection.readout.contains("guards attack on sight"))
        #expect(panel.bountySection.readout.contains("Crime faction here: Hold"))
        #expect(panel.theftSection.readout.contains("Ring × 2"))
        #expect(panel.membershipSection.readout.contains("Guild rank 2"))
        #expect(panel.membershipSection.readout.contains("Guard: polices Hold"))
        #expect(panel.vendorSection.readout.contains("Hours: 8-20 · open now"))
        #expect(panel.bountySection.factionControl.titleOfSelectedItem == "Hold")
        #expect(panel.membershipSection.factionControl.itemTitles == ["Guild", "Hold", "Shop"])
        #expect(panel.vendorSection.overrideControl.titleOfSelectedItem
            == FactionVendorSection.resolvedTitle)
        // One snapshot per tick for all four sections.
        let reads = providers.crimeFactions.snapshotReads
        panel.refreshSections()
        #expect(providers.crimeFactions.snapshotReads == reads + 1)
    }

    @Test
    func theControlsSendWhatTheFieldsHold() throws {
        let providers = FakeWorldProviders()
        providers.crimeFactions.snapshot = CrimeFactionSnapshotFixture.snapshot()
        let panel = try Self.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        let bounty = panel.bountySection
        bounty.amountControl.stringValue = "-25"
        bounty.violentControl.state = .on
        sendScriptsControl(bounty.addControl)
        #expect(providers.crimeFactions.bountyChanges.first?.gold == -25)
        #expect(providers.crimeFactions.bountyChanges.first?.violent == true)
        bounty.amountControl.stringValue = "lots"
        sendScriptsControl(bounty.addControl)
        #expect(
            providers.crimeFactions.bountyChanges.last?.gold == CrimeBountySection.defaultAmount
        )
        for control in [bounty.clearControl, bounty.guardCheckControl, bounty.resistControl] {
            sendScriptsControl(control)
        }
        #expect(providers.crimeFactions.clearCount == 1)
        #expect(providers.crimeFactions.guardChecks == 1)
        #expect(providers.crimeFactions.resistCount == 1)

        let members = panel.membershipSection
        members.factionControl.selectItem(at: 1)
        sendScriptsControl(members.factionControl)
        #expect(providers.membershipFactionSelection == CrimeFactionSnapshotFixture.hold.key)
        members.rankControl.stringValue = "300"
        sendScriptsControl(members.joinControl)
        #expect(providers.crimeFactions.joins == [Int8.max])
        for control in [members.leaveControl, members.crosshairControl, members.playerControl] {
            sendScriptsControl(control)
        }
        #expect(providers.crimeFactions.leaveCount == 1)
        #expect(providers.crimeFactions.crosshairPicks == 1)
        #expect(providers.crimeFactions.playerPicks == 1)
    }

    @Test
    func theVendorOverrideIsTheOneResettableSetting() throws {
        let providers = FakeWorldProviders()
        providers.crimeFactions.snapshot = CrimeFactionSnapshotFixture.snapshot()
        let panel = try Self.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }
        let vendor = panel.vendorSection
        #expect(!vendor.isOverridden)

        vendor.overrideControl.selectItem(at: 1)
        sendScriptsControl(vendor.overrideControl)
        #expect(providers.vendorOverrideSelection == CrimeFactionSnapshotFixture.shop.key)
        #expect(vendor.isOverridden)
        sendScriptsControl(vendor.barterControl)
        #expect(providers.crimeFactions.barterCount == 1)

        vendor.performResetToDefaults()
        #expect(providers.vendorOverrideSelection == nil)
        #expect(!vendor.isOverridden)
    }

    /// Every section fits the inspector column: the widest row is the labeled
    /// faction popup, pinned narrower than the content width.
    @Test
    func theSectionsFitThePanelColumn() throws {
        let providers = FakeWorldProviders()
        providers.crimeFactions.snapshot = CrimeFactionSnapshotFixture.snapshot()
        let panel = try Self.panel(providers: providers)
        panel.view.frame = NSRect(x: 0, y: 0, width: PanelMetrics.panelWidth, height: 900)
        panel.view.layoutSubtreeIfNeeded()
        for section in panel.crimeFactionSections {
            #expect(section.view.fittingSize.width <= PanelMetrics.contentWidth + 1)
        }
    }
}
