// The bounty statistics from docs/engine/crime-reports.md, Statistics: a hold
// statistic follows the bounty both ways; the totals grow only on an increase.

@testable import OpenSkyCrime
import OpenSkyCrimeFixtures
@testable import OpenSkyCrimeInterface
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

@MainActor
struct BountyStatisticsTests {
    @Test func aRiseSetsTheHoldStatAndGrowsTheTotals() {
        let commands = BountyStatistics.commands(
            editorID: "CrimeFactionWhiterun", counts: true, old: 40, new: 1040
        )
        #expect(commands == [
            .setStat("Whiterun Bounty", to: 1040),
            .raiseStat("Largest Bounty", to: 1040),
            .incrementStat("Total Lifetime Bounty", by: 1000)
        ])
    }

    @Test func aFallOnlyMovesTheHoldStat() {
        let commands = BountyStatistics.commands(
            editorID: "CrimeFactionPale", counts: true, old: 1040, new: 0
        )
        #expect(commands == [.setStat("The Pale Bounty", to: 0)])
    }

    @Test func anUncountedOrUnchangedFactionChangesNothing() {
        #expect(BountyStatistics.commands(
            editorID: "CrimeFactionRift", counts: false, old: 0, new: 100
        ).isEmpty)
        #expect(BountyStatistics.commands(
            editorID: "CrimeFactionRift", counts: true, old: 100, new: 100
        ).isEmpty)
        #expect(BountyStatistics.commands(editorID: nil, counts: true, old: 0, new: 5) == [
            .raiseStat("Largest Bounty", to: 5), .incrementStat("Total Lifetime Bounty", by: 5)
        ])
    }

    @Test func theCoordinatorCountsEachChangeOfTheLedgerOnce() throws {
        let hold = CrimeFixture.key(CrimeFixture.Factions.hold)
        let coordinator = try Self.coordinator()
        coordinator.reporter?.modifyCrimeGold(by: 30, violent: false, of: hold)
        coordinator.advanceReports()
        #expect(Self.stats(coordinator.takeCommands()) == [
            .raiseStat("Largest Bounty", to: 30), .incrementStat("Total Lifetime Bounty", by: 30)
        ])

        coordinator.reporter?.modifyCrimeGold(by: 1000, violent: true, of: hold)
        coordinator.advanceReports()
        coordinator.advanceReports()
        #expect(Self.stats(coordinator.takeCommands()) == [
            .raiseStat("Largest Bounty", to: 1030),
            .incrementStat("Total Lifetime Bounty", by: 1000)
        ])

        coordinator.reporter?.modifyCrimeGold(by: -1000, violent: true, of: hold)
        coordinator.advanceReports()
        #expect(Self.stats(coordinator.takeCommands()).isEmpty)
    }

    @Test func ridingAnOwnedHorseCountsAHorseNotAnItem() throws {
        let coordinator = try Self.coordinator()
        let owner = ReferenceOwner.faction(
            CrimeFixture.key(CrimeFixture.Factions.hold), requiredRank: -1
        )
        coordinator.reporter?.reportHorseTheft(of: CrimeFixture.key(0x7000), owner: owner)
        let commands = coordinator.takeCommands()
        #expect(commands.contains(.incrementStat("Horses Stolen", by: 1)))
        #expect(!commands.contains(.incrementStat("Items Stolen", by: 1)))
    }

    static func coordinator(witnesses: [ReferenceKey] = []) throws -> CrimeCoordinator {
        let world = FakeCrimeSessionWorld()
        let shop = CellSceneLocation.interior(FormID(0x900))
        world.currentCellLocation = shop
        world.references = FakeCrimeReferences(cell: shop)
        world.cellLinks[shop] = FormID(CrimeFixture.Locations.shop)
        let coordinator = try CrimeCoordinator(
            world: world,
            data: CrimeSessionData(
                runtime: CrimeFixture.runtime(),
                locations: CrimeFixture.locationStore(),
                pluginName: CrimeFixture.pluginName
            ),
            witnesses: FixedCrimeWitnesses(watching: .player, by: witnesses),
            storyEvents: nil
        )
        coordinator.advanceReports()
        return coordinator
    }

    static func stats(_ commands: [CrimeCommand]) -> [CrimeCommand] {
        commands.filter {
            switch $0 {
            case .setStat, .raiseStat, .incrementStat: true
            default: false
            }
        }
    }
}
