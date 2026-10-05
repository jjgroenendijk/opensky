// M21 panel acceptance: one run through `World > Crime & Factions` on a real
// `GameViewController` with the faction runtime and crime reporter over
// `CrimeFixture`'s synthetic load order, plus the new Asset Browser families.
// Readouts are found by accessibility id, so the run needs no UI automation.

import AppKit
@testable import FeaturesTesting
@testable import OpenSky
@testable import OpenSkyCrime
@testable import OpenSkyFactions
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPreview
import TagsTesting
import Testing

@Suite(.tags(.acceptance))
@MainActor
struct CrimeFactionsAcceptancePanelTests {
    /// A controller with factions and crime wired over the fixture load order.
    static func controller() throws -> GameViewController {
        let controller = GameViewController()
        let factions = try CrimeFixture.factionStore()
        let file = try CrimeFixture.file()
        controller.factions.attach(world: controller.factionWorld)
        controller.factions.wire(
            factions: factions,
            relationships: RelationshipStore(plugins: [(CrimeFixture.pluginName, file)]),
            baselines: nil,
            pluginName: CrimeFixture.pluginName
        )
        controller.crime.attach(world: controller.crimeWorld)
        controller.crime.wire(
            runtime: CrimeRuntime(store: controller.worldState, factions: factions),
            locations: nil,
            pluginName: CrimeFixture.pluginName
        )
        return controller
    }

    @Test
    func theCrimeDestinationRunsTheWholeAcceptanceFlow() throws {
        let controller = try Self.controller()
        let panel = try Self.buildPanel(providers: controller)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        Self.readTheCleanRecord(panel)
        Self.raiseAndClearABounty(panel, controller: controller)
        Self.resistTheHold(panel, controller: controller)
        try Self.joinAndLeaveAFaction(panel, controller: controller)
    }

    private static func buildPanel(
        providers: GameViewController
    ) throws -> CrimeFactionPanelViewController {
        try buildWorldPanel("crimeFactions", providers: providers)
    }

    /// Scope points 2 and 3: an empty ledger, no target, no stolen goods, and
    /// the player's own empty membership list — every readout says what it has
    /// rather than going blank.
    private static func readTheCleanRecord(_ panel: CrimeFactionPanelViewController) {
        #expect(readout("CrimeBountyStatsLabel", in: panel)
            .contains("Bounty: 0 gold with 0 faction(s)"))
        let theft = readout("CrimeTheftStatsLabel", in: panel)
        #expect(theft.contains("Target: none"))
        #expect(theft.contains("Stolen items carried: 0"))
        #expect(readout("FactionMembershipStatsLabel", in: panel)
            .contains("Player — 0 membership(s)"))
        #expect(readout("FactionVendorStatsLabel", in: panel)
            .contains("the player: not a merchant"))
        // Only the two factions that track crime are offered for a bounty.
        #expect(panel.bountySection.factionControl.itemTitles
            == ["CrimeFactionHold", "CrimeFactionTolerant"])
    }

    /// Scope point 4: Add goes through `CrimeRuntime.modifyCrimeGold`, the door
    /// `Faction.ModCrimeGold` uses, into the chosen half; Clear drops both.
    private static func raiseAndClearABounty(
        _ panel: CrimeFactionPanelViewController,
        controller: GameViewController
    ) {
        let hold = CrimeFixture.key(CrimeFixture.Factions.hold)
        let bounty = panel.bountySection
        bounty.amountControl.stringValue = "1500"
        bounty.violentControl.state = .on
        sendScriptsControl(bounty.addControl)
        #expect(controller.crime.crimeGold(of: hold) == 1500)
        #expect(controller.crime.reporter?.runtime.crimeGold(of: hold, violent: true) == 1500)

        bounty.refreshReadout()
        let text = readout("CrimeBountyStatsLabel", in: panel)
        #expect(text.contains("CrimeFactionHold: 1500 (non-violent 0, violent 1500)"))
        // The fixture hold arrests and does not attack on sight.
        #expect(text.contains("guards confront"))

        sendScriptsControl(bounty.clearControl)
        #expect(controller.crime.crimeGold(of: hold) == 0)
        bounty.refreshReadout()
        #expect(readout("CrimeBountyStatsLabel", in: panel)
            .contains("Cleared 1500 gold owed to CrimeFactionHold."))
    }

    /// Scope point 4: resisting goes through `resistArrest`, the path a closed
    /// arrest conversation takes; the guard check refuses without a guard.
    private static func resistTheHold(
        _ panel: CrimeFactionPanelViewController,
        controller: GameViewController
    ) {
        let hold = CrimeFixture.key(CrimeFixture.Factions.hold)
        sendScriptsControl(panel.bountySection.resistControl)
        #expect(controller.crime.guards.resisted.contains(hold))
        panel.bountySection.refreshReadout()
        #expect(readout("CrimeBountyStatsLabel", in: panel)
            .contains("Last guard: Resisted arrest with CrimeFactionHold."))

        sendScriptsControl(panel.bountySection.guardCheckControl)
        panel.bountySection.refreshReadout()
        #expect(readout("CrimeBountyStatsLabel", in: panel)
            .contains("the player is nobody's guard"))
    }

    /// Scope points 3 and 4: Join and Leave go through `joinFaction` and
    /// `leaveFaction`, the calls `Actor.AddToFaction` and
    /// `Actor.RemoveFromFaction` make.
    private static func joinAndLeaveAFaction(
        _ panel: CrimeFactionPanelViewController,
        controller: GameViewController
    ) throws {
        let shopkeepers = CrimeFixture.key(CrimeFixture.Factions.shopkeepers)
        let members = panel.membershipSection
        let titles = members.factionControl.itemTitles
        let index = try #require(titles.firstIndex(of: "ShopkeeperFaction"))
        members.factionControl.selectItem(at: index)
        sendScriptsControl(members.factionControl)
        members.rankControl.stringValue = "1"
        sendScriptsControl(members.joinControl)
        #expect(controller.factions.runtime?.rank(of: .player, in: shopkeepers) == 1)
        members.refreshReadout()
        #expect(readout("FactionMembershipStatsLabel", in: panel)
            .contains("ShopkeeperFaction rank 1"))

        sendScriptsControl(members.leaveControl)
        #expect(controller.factions.runtime?.isMember(.player, of: shopkeepers) == false)
    }

    /// FACT, RELA, and ASTP are browsable from the load-order record surface,
    /// whose inspector prints their text dumps.
    @Test
    func theAssetBrowserBrowsesTheThreeFactionRecordTypes() throws {
        let types: [ReferenceRecordType] = [.faction, .relationship, .associationType]
        #expect(types.map(\.fourCC) == ["FACT", "RELA", "ASTP"])

        let panel = PreviewViewController()
        panel.startupErrorMessage = "test"
        panel.loadViewIfNeeded()
        let recordIndex = try #require(
            PreviewCategory.allCases.firstIndex(of: .referenceRecords)
        )
        panel.categoryPopUp.selectItem(at: recordIndex)
        panel.categoryChanged()
        let titles = panel.recordTypePopUp.itemTitles
        for type in types {
            #expect(titles.contains(type.title), "\(type.fourCC) is not browsable")
        }
    }

    private static func readout(
        _ identifier: String,
        in panel: CrimeFactionPanelViewController
    ) -> String {
        scriptsReadout(identifier, in: panel.view) ?? ""
    }
}
