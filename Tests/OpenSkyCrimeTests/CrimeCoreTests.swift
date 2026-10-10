// The pure crime rules: readout sentences, the panel's faction lists, and what
// the hostility derivation reads about the player's bounties. No game-derived
// bytes.

@testable import OpenSkyCrime
import OpenSkyCrimeFixtures
@testable import OpenSkyCrimeInterface
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorldState
import Testing

@MainActor
struct CrimeCoreTests {
    private static let hold = CrimeFixture.key(CrimeFixture.Factions.hold)

    @Test func anOutcomeLineNamesTheBountyOrTheRefusal() {
        let charged = CrimeOutcome(gold: 40, faction: Self.hold, recorded: true, refusal: nil)
        let refused = CrimeOutcome(gold: 0, faction: nil, recorded: false, refusal: .unwitnessed)
        #expect(CrimeCore.outcomeText(charged, label: "Assault", factionName: "Hold")
            == "Assault: 40 bounty with Hold.")
        #expect(CrimeCore.outcomeText(refused, label: "Murder", factionName: nil)
            == "Murder: no bounty with nobody — unwitnessed.")
    }

    @Test func theCrimeListOffersOnlyFactionsThatTrackCrime() throws {
        let options = try CrimeCore.factionOptions(CrimeFixture.factionStore())
        #expect(options.crime.map(\.name) == ["CrimeFactionHold", "CrimeFactionTolerant"])
        #expect(options.all.count == 4)
        #expect(options.vendors.isEmpty)
    }

    @Test func guardHostilityCarriesOnlyOwedFactionsAndTheGuardFaction() throws {
        let store = try CrimeFixture.factionStore()
        let runtime = try CrimeFixture.runtime()
        runtime.setCrimeGold(1500, of: Self.hold)
        let hostility = CrimeCore.guardHostility(
            ledger: runtime.ledger(), factions: store, resisted: [Self.hold]
        )
        #expect(hostility.bounties == [Self.hold: 1500])
        #expect(hostility.crimeValues[Self.hold] != nil)
        #expect(hostility.guardFaction == CrimeFixture.key(CrimeFixture.Factions.guards))
        #expect(hostility.resisted == [Self.hold])
    }

    @Test func aPursuingGuardRepathsOnlyOnceThePlayerMovedAway() {
        let half = CrimeCore.guardRepathDistance
        #expect(CrimeCore.needsRepath(lastTarget: nil, player: .zero))
        #expect(!CrimeCore.needsRepath(lastTarget: .zero, player: [half / 2, 0, 0]))
        #expect(CrimeCore.needsRepath(lastTarget: .zero, player: [half, 0, 0]))
    }

    @Test func theOwnerNameSaysWhoseAndWhichRank() throws {
        let store = try CrimeFixture.factionStore()
        #expect(CrimeCore.ownerName(nil, in: store) == nil)
        #expect(CrimeCore.ownerName(.faction(Self.hold, requiredRank: 2), in: store)
            == "CrimeFactionHold (rank 2 or higher)")
    }

    @Test func aSettlementLineSaysHowItWasPaidAndWhereThePlayerStands() {
        let fine = ArrestSettlement(
            faction: Self.hold, bounty: 40, goldPaid: 40, confiscated: [],
            evidenceChest: nil, sentenceDays: 0, releaseMarker: nil
        )
        let jail = ArrestSettlement(
            faction: Self.hold, bounty: 300, goldPaid: 0, confiscated: [],
            evidenceChest: nil, sentenceDays: 3,
            releaseMarker: CrimeFixture.key(CrimeFixture.Links.jailMarker)
        )
        #expect(CrimeCore.settlementText(fine, factionName: "Hold", moved: false)
            == "Paid 40 gold to Hold for a 40 bounty; 0 stolen items seized.")
        #expect(CrimeCore.settlementText(jail, factionName: "Hold", moved: false)
            == "Served 3 days to Hold for a 300 bounty; 0 stolen items seized, "
            + "jail marker not resident.")
    }

    @Test func theGuardKeyIsTheSameForBothActions() {
        let guardKey = CrimeFixture.key(CrimeFixture.Actors.resident)
        #expect(CrimeCore.guardKey(of: .pursue(guardKey: guardKey, crimeFaction: Self.hold))
            == guardKey)
        #expect(CrimeCore.guardKey(
            of: .confront(guardKey: guardKey, crimeFaction: Self.hold, bounty: 1)
        ) == guardKey)
    }
}
