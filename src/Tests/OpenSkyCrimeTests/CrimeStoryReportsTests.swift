// The story events an arrest and a served sentence raise, the scripted owner, and the
// favour allowance the ownership world reads.

@testable import OpenSkyCrime
import OpenSkyCrimeFixtures
@testable import OpenSkyCrimeInterface
import OpenSkyFeaturesTesting
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState
import Testing

@MainActor
struct CrimeStoryReportsTests {
    private static let faction = CrimeFixture.key(CrimeFixture.Factions.shopkeepers)

    @Test func anArrestWithASentenceAndTheServedTimeRaiseThreeEvents() {
        let recorder = StoryEventRecorder()
        let settlement = ArrestSettlement(
            faction: Self.faction, bounty: 40, goldPaid: 0, confiscated: [],
            evidenceChest: nil, sentenceDays: 1, releaseMarker: nil
        )
        recorder.reportArrest(by: .generated(3), settlement: settlement, crime: nil)
        recorder.reportServedTime(JailStay(
            faction: Self.faction, nonViolentGold: 40, violentGold: 0, sentenceDays: 1,
            exteriorMarker: .generated(4), belongings: nil, outfit: [], arrestedIn: nil
        ))
        #expect(recorder.events.count == 3)
        #expect(["ARRT", "JAIL", "STIJ"].map { recorder.events($0).count } == [1, 1, 1])
    }

    @Test func aScriptedOwnerIsKeptAndRaisesTheRevision() throws {
        let coordinator = try CrimeCoordinator(
            world: FakeCrimeSessionWorld(),
            data: CrimeSessionData(
                runtime: CrimeFixture.runtime(), locations: nil,
                pluginName: CrimeFixture.pluginName
            ),
            witnesses: nil, storyEvents: nil
        )
        #expect(coordinator.scriptedOwner == nil)
        coordinator.scriptedOwner = { _ in .some(nil) }
        #expect(coordinator.scriptedOwner != nil)
    }

    @Test func aScriptSetCellOwnerWinsOverTheCellsOwnAndIsInherited() throws {
        let shop = CellSceneLocation.interior(FormID(0x900))
        let fake = FakeCrimeSessionWorld()
        fake.references = FakeCrimeReferences(cell: shop)
        fake.cellOwners[shop] = RecordOwnership(owner: FormID(CrimeFixture.Factions.hold))
        let world = try CrimeOwnershipWorld(
            world: fake,
            data: CrimeSessionData(
                runtime: CrimeFixture.runtime(), locations: nil,
                pluginName: CrimeFixture.pluginName
            )
        )
        let hold = CrimeFixture.key(CrimeFixture.Factions.hold)
        #expect(world.crimeOwner(of: .generated(7)) == .faction(hold, requiredRank: 0))

        let owner = CrimeFixture.key(CrimeFixture.Actors.resident)
        world.scriptedOwner = { $0 == CrimeFixture.key(0x900) ? .some(.actor(owner)) : nil }
        #expect(world.cellOwner(at: shop) == .actor(owner))
        #expect(world.crimeOwner(of: .generated(7)) == .actor(owner))
        #expect(world.cellOwner(at: .interior(FormID(0x901))) == nil)
    }

    @Test func aFactionWithoutAnAllowanceHasNone() throws {
        let world = try CrimeOwnershipWorld(
            world: FakeCrimeSessionWorld(),
            data: CrimeSessionData(
                runtime: CrimeFixture.runtime(), locations: nil,
                pluginName: CrimeFixture.pluginName
            )
        )
        #expect(world.favourAllowance(in: .generated(99)) == nil)
    }
}
