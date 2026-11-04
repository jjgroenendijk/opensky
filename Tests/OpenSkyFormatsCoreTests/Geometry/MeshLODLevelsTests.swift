// The index counts of a BSLODTriShape's three detail levels.

@testable import OpenSkyFormatsCore
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct MeshLODLevelsTests {
    @Test
    func fallingCountsArePrefixes() {
        #expect(MeshLODLevels.indexCounts(triangleCounts: [100, 60, 20], indexCount: 300)
            == [300, 180, 60])
    }

    @Test
    func otherCountsAreRuns() {
        #expect(MeshLODLevels.indexCounts(triangleCounts: [20, 30, 50], indexCount: 300)
            == [300, 150, 60])
    }

    @Test
    func countsThatDoNotFitGiveOneLevel() {
        #expect(MeshLODLevels.indexCounts(triangleCounts: [200, 60, 20], indexCount: 300).isEmpty)
        #expect(MeshLODLevels.indexCounts(triangleCounts: [0, 0, 0], indexCount: 300).isEmpty)
        #expect(MeshLODLevels.indexCounts(triangleCounts: [100, 100, 100], indexCount: 300).isEmpty)
        #expect(MeshLODLevels.indexCounts(triangleCounts: [], indexCount: 300).isEmpty)
    }
}
