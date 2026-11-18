// UESP Skyrim:Crime: a victim killed by one blow costs the murder bounty only.
// A second blow before the death keeps the assault.

@testable import OpenSkyCrime
import OpenSkyCrimeFixtures
@testable import OpenSkyCrimeInterface
import OpenSkyFeaturesTesting
@testable import OpenSkyGameData
import Testing

@MainActor
struct OneHitKillTests {
    private static let hold = CrimeFixture.key(CrimeFixture.Factions.hold)
    private static let victim = CrimeFixture.key(CrimeFixture.Actors.resident)
    private static let witness = CrimeFixture.key(CrimeFixture.Actors.shopkeeper)

    @Test func aOneBlowKillChargesMurderOnly() throws {
        let coordinator = try BountyStatisticsTests.coordinator(witnesses: [Self.witness])
        coordinator.reportAssault(on: Self.victim, wasHostile: false)
        #expect(coordinator.crimeGold(of: Self.hold) > 0)
        _ = coordinator.takeCommands()
        coordinator.reportMurder(of: Self.victim)

        #expect(coordinator.crimeGold(of: Self.hold) == 1000)
        #expect(coordinator.takeCommands().contains(.incrementStat("Assaults", by: -1)))
        #expect(coordinator.pendingReports.map(\.violent) == [true])
    }

    @Test func aSecondBlowKeepsTheAssault() throws {
        let coordinator = try BountyStatisticsTests.coordinator(witnesses: [Self.witness])
        coordinator.reportAssault(on: Self.victim, wasHostile: false)
        let assault = coordinator.crimeGold(of: Self.hold)
        coordinator.reportAssault(on: Self.victim, wasHostile: true)
        coordinator.reportMurder(of: Self.victim)

        #expect(coordinator.crimeGold(of: Self.hold) > assault)
        #expect(!coordinator.takeCommands().contains(.incrementStat("Assaults", by: -1)))
        #expect(coordinator.pendingReports.count == 2)
    }
}
