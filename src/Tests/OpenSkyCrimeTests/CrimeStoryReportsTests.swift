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

    @Test func anArrestAndAServedSentenceEachRaiseOneEvent() {
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
        #expect(recorder.events.count == 2)
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
