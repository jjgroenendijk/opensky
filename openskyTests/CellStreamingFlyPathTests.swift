// Pure scripted fly-path tests: pin waypoint order, interpolation endpoints,
// and 5x5 union size without Metal or game data. Runtime settlement, memory,
// unload, and build-count gates live in `openskycli bench --fly-path`.

@testable import opensky
import Testing

struct CellStreamingFlyPathTests {
    @Test
    func waypointsCrossEastThenNorth() {
        let start = CellCoordinate(x: 6, y: -2)
        #expect(CellStreamingFlyPath.waypoints(start: start) == [
            start,
            CellCoordinate(x: 7, y: -2),
            CellCoordinate(x: 7, y: -1)
        ])
    }

    @Test
    func positionsEndAtNextCellCenter() {
        let start = CellCoordinate(x: 6, y: -2)
        let end = CellCoordinate(x: 7, y: -2)
        let positions = CellStreamingFlyPath.positions(from: start, to: end, samples: 4)
        #expect(positions.count == 4)
        #expect(positions.last == CellGridManager.cellCenter(of: end))
        #expect(positions[0].x > CellGridManager.cellCenter(of: start).x)
    }

    @Test
    func adjacentFiveByFiveGridsNeedThirtyFiveUniqueBuilds() {
        let cells = CellStreamingFlyPath.expectedCells(
            start: CellCoordinate(x: 6, y: -2),
            radius: CellGridManager.defaultRadius
        )
        #expect(cells.count == 35)
    }
}
