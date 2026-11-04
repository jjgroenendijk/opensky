// The game's mesh LOD distances pick a detail level.

@testable import OpenSkyRenderCore
import Testing

struct MeshLODDistancesTests {
    @Test
    func levelsFollowTheDistances() {
        let distances = MeshLODDistances(level1: 2000, level2: 4000)
        #expect(distances.level(distance: 100) == 0)
        #expect(distances.level(distance: 2500) == 1)
        #expect(distances.level(distance: 9000) == 2)
    }

    @Test
    func zeroNeverSwitches() {
        #expect(MeshLODDistances.off.isOn == false)
        #expect(MeshLODDistances(level1: 0, level2: 4000).level(distance: 3000) == 0)
        #expect(MeshLODDistances(level1: 2000, level2: 0).level(distance: 1e6) == 1)
    }
}
