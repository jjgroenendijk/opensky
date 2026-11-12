// The tree reads the progression readout makes: one row per skill, the tree count
// cache that building them fills, and which skills carry a perk tree.

import OpenSkyFeaturesTesting
import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyProgression
import OpenSkyProgressionInterface
import Testing

@MainActor
struct ProgressionTreeReaderTests {
    @Test func theSnapshotListsEverySkillAndCountsItsTrees() throws {
        let coordinator = try ProgressionCoordinatorFixture.make(world: FakeProgressionWorld())
        let snapshot = coordinator.snapshot
        #expect(snapshot.isAvailable)
        #expect(snapshot.skills.count == ActorValueIdentity.skillIndices.count)
        #expect(snapshot.perkTreeCache.skillCount > 0)
    }

    @Test func aSkillWithoutInformationHasNoPerkTree() throws {
        let coordinator = try ProgressionCoordinatorFixture.make(world: FakeProgressionWorld())
        #expect(!coordinator.treeReader.hasPerkTree(-1))
        #expect(coordinator.beastTree == nil)
    }
}
