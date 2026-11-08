// Distant water covers the LOD area once, and leaves the loaded cells to their
// own water planes.

import OpenSkyFormatsCore
@testable import OpenSkyTerrain
import Testing

struct LODWaterLayoutTests {
    private typealias Rectangle = LODWaterLayout.Rectangle
    private let area = Rectangle(origin: CellCoordinate(x: -4, y: -4), width: 8, height: 8)

    private func cells(_ rectangles: [Rectangle]) -> [CellCoordinate] {
        rectangles.flatMap { rectangle in
            (0 ..< rectangle.height).flatMap { dy in
                (0 ..< rectangle.width).map { dx in
                    CellCoordinate(x: rectangle.origin.x + dx, y: rectangle.origin.y + dy)
                }
            }
        }
    }

    @Test func nothingLoadedCoversTheWholeArea() {
        #expect(LODWaterLayout.rectangles(area: area, hidden: []) == [area])
    }

    @Test func theLoadedBlockIsAHoleAndNoCellIsCoveredTwice() {
        var hidden: Set<CellCoordinate> = []
        for x in Int32(-1) ... 1 {
            for y in Int32(0) ... 2 {
                hidden.insert(CellCoordinate(x: x, y: y))
            }
        }
        let covered = cells(LODWaterLayout.rectangles(area: area, hidden: hidden))
        #expect(covered.count == 64 - 9)
        #expect(Set(covered).count == covered.count)
        #expect(Set(covered).isDisjoint(with: hidden))
    }

    @Test func aHoleAtTheEdgeLeavesNoEmptyStrip() {
        let hidden: Set<CellCoordinate> = [CellCoordinate(x: -4, y: -4)]
        let rectangles = LODWaterLayout.rectangles(area: area, hidden: hidden)
        #expect(rectangles.count == 2)
        #expect(cells(rectangles).count == 63)
    }

    @Test func loadedCellsOutsideTheAreaAreIgnored() {
        let hidden: Set<CellCoordinate> = [CellCoordinate(x: 40, y: 40)]
        #expect(LODWaterLayout.rectangles(area: area, hidden: hidden) == [area])
    }
}
