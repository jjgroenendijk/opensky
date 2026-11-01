// A friend's faction lets the player take an item up to the friend's allowance
// without theft (UESP "Skyrim:Disposition", Relationship Rank).

@testable import OpenSkyCrime
import OpenSkyCrimeFixtures
@testable import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
import OpenSkyFeaturesTesting
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState
import Testing

@MainActor
struct FavourAllowanceTests {
    private static let family = CrimeFixture.key(CrimeFixture.Factions.shopkeepers)
    private static let friend = CrimeFixture.key(CrimeFixture.Actors.resident)
    private static let stranger = CrimeFixture.key(CrimeFixture.Actors.shopkeeper)
    private static let cheap = FormID(0xA01)
    private static let dear = FormID(0xA02)

    /// Answers one faction-owned reference and two item values.
    private final class World: CrimeWorld {
        var owner: ReferenceOwner?
        var allowance: Int32?

        func crimeOwner(of _: ReferenceKey) -> ReferenceOwner? {
            owner
        }

        func crimeFaction(in _: CellSceneLocation?) -> ReferenceKey? {
            nil
        }

        func crimeCell(of _: ReferenceKey) -> CellSceneLocation? {
            nil
        }

        func crimeItemValue(of item: FormID) -> Int64 {
            item == FavourAllowanceTests.cheap ? 25 : 26
        }

        func crimeActor(_: ReferenceKey) -> CrimeActor {
            .player
        }

        func favourAllowance(in _: ReferenceKey) -> Int32? {
            allowance
        }
    }

    private static func gold(_ state: ActorRelationshipState, member: Bool = true) -> Int32? {
        FavourAllowance.gold(
            in: family,
            playerRelationships: state,
            memberships: { key in
                key == friend && member
                    ? CrimeFixture.state([(CrimeFixture.Factions.shopkeepers, 0)]) : nil
            },
            settings: .vanilla
        )
    }

    @Test func eachRankHasItsSettingAndAnAcquaintanceNone() {
        let settings = CrimeSettings.vanilla
        #expect(settings.favourAllowance(forRank: 0) == nil)
        #expect(settings.favourAllowance(forRank: 1) == 25)
        #expect(settings.favourAllowance(forRank: 2) == 50)
        #expect(settings.favourAllowance(forRank: 3) == 100)
        #expect(settings.favourAllowance(forRank: 4) == 500)
        #expect(settings.favourAllowance(forRank: 9) == 500)
    }

    @Test func theFirstFriendRankStaysWhenTheRankRises() {
        let state = ActorRelationshipState()
            .setting(0, toward: Self.friend)
            .setting(1, toward: Self.friend)
            .setting(3, toward: Self.friend)
        #expect(state.rank(toward: Self.friend) == 3)
        #expect(state.firstFriendRank(toward: Self.friend) == 1)
        #expect(Self.gold(state) == 25)
    }

    @Test func onlyAFriendWhoBelongsToTheFactionGrantsAnAllowance() {
        let ally = ActorRelationshipState().setting(3, toward: Self.friend)
        #expect(Self.gold(ally) == 100)
        #expect(Self.gold(ally, member: false) == nil)
        #expect(Self.gold(ally.setting(-1, toward: Self.friend)) == nil)
        #expect(Self.gold(ActorRelationshipState().setting(4, toward: Self.stranger)) == nil)
    }

    @Test func aCheapFactionItemIsNoTheftAndADearOneStillIs() throws {
        let owner = ReferenceOwner.faction(Self.family, requiredRank: 0)
        let world = World()
        world.owner = owner
        world.allowance = 25
        let reporter = try CrimeReporter(runtime: CrimeFixture.runtime(), world: world)
        let chest = CrimeFixture.key(0x700)

        #expect(reporter.verdict(on: chest, item: Self.cheap) == .permitted(owner))
        #expect(reporter.verdict(on: chest, item: Self.dear).isTheft)
        #expect(reporter.verdict(on: chest).isTheft)
        #expect(reporter.verdict(on: chest, item: Self.cheap, by: Self.stranger).isTheft)
    }

    @Test func anItemTheFriendOwnsThemselvesIsStillTheft() throws {
        let world = World()
        world.owner = .actor(Self.friend)
        world.allowance = 500
        let reporter = try CrimeReporter(runtime: CrimeFixture.runtime(), world: world)
        #expect(reporter.verdict(on: CrimeFixture.key(0x700), item: Self.cheap).isTheft)
    }
}
