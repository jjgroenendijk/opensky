// Followers wait at the jail door during a sentence, and those near it follow again.

@testable import OpenSkyCrime
import OpenSkyCrimeFixtures
@testable import OpenSkyCrimeInterface
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

@MainActor
struct CrimeJailFollowerTests {
    private static let hold = CrimeFixture.key(CrimeFixture.Factions.hold)
    private static let marker = CrimeFixture.key(CrimeFixture.Links.jailMarker)
    private static let near = ReferenceKey.generated(11)
    private static let far = ReferenceKey.generated(12)

    private static func arrested() throws -> (FakeCrimeSessionWorld, CrimeCoordinator) {
        let world = FakeCrimeSessionWorld()
        world.inventory = try FakeCrimeInventory()
        world.jailCell = .interior(FormID(0x950))
        world.gameSeconds = 0
        world.currentCellLocation = .interior(FormID(0x900))
        world.followers = [near, far]
        let coordinator = try CrimeCoordinator(
            world: world,
            data: CrimeSessionData(
                runtime: CrimeFixture.runtime(),
                locations: CrimeFixture.locationStore(),
                pluginName: CrimeFixture.pluginName
            ),
            witnesses: nil,
            storyEvents: nil
        )
        coordinator.reporter?.runtime.setCrimeGold(300, of: hold)
        _ = coordinator.settleArrest(with: hold, .jail())
        world.currentCellLocation = world.jailCell
        coordinator.advanceJail()
        return (world, coordinator)
    }

    @Test func followersWaitAtTheJailDoorAndTheNearOnesFollowAfterTheSentence() throws {
        let (world, coordinator) = try Self.arrested()
        #expect(world.parked == [Self.near: Self.marker, Self.far: Self.marker])
        #expect(coordinator.jailFollowers == [Self.near, Self.far])

        world.markerDistances = [Self.near: 300, Self.far: 50000]
        #expect(coordinator.serveSentence())
        #expect(world.released == [Self.near])
        #expect(coordinator.jailFollowers == [Self.far])
    }

    @Test func anEscapeReleasesTheWaitingFollowersToo() throws {
        let (world, coordinator) = try Self.arrested()
        world.markerDistances = [Self.near: 0, Self.far: 0]
        world.currentCellLocation = .interior(FormID(0x900))
        coordinator.advanceJail()
        #expect(coordinator.jailStay == nil)
        #expect(world.released == [Self.near, Self.far])
    }
}
