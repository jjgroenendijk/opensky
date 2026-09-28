// Streaming grid manager math (todo 3.2 grid manager): floor-division cell
// mapping (incl. negative coords + exact boundaries), desired-grid contents,
// one-move diffing, hysteresis no-thrash, radius parameter. Pure math,
// synthetic positions (AGENTS.md testing rule).

@testable import opensky
import simd
import Testing

struct CellGridManagerTests {
    private let cellSize: Float = 4096

    // MARK: - cellCoordinate(for:) floor mapping

    @Test
    func originMapsToCellZeroZero() {
        let coordinate = CellGridManager.cellCoordinate(for: SIMD3<Float>(0, 0, 0))
        #expect(coordinate == CellCoordinate(x: 0, y: 0))
    }

    @Test
    func positiveInteriorMapsToItsCell() {
        let coordinate = CellGridManager.cellCoordinate(for: SIMD3<Float>(6144, 10240, 0))
        #expect(coordinate == CellCoordinate(x: 1, y: 2))
    }

    @Test
    func negativePositionUsesFloorNotTruncation() {
        // X=-1 must land in cell -1, not cell 0 (truncation toward zero would
        // give 0 -- docs/decisions/coordinates.md is explicit about this).
        let coordinate = CellGridManager.cellCoordinate(for: SIMD3<Float>(-1, -1, 0))
        #expect(coordinate == CellCoordinate(x: -1, y: -1))
    }

    @Test
    func negativeInteriorMapsToItsCell() {
        let coordinate = CellGridManager.cellCoordinate(for: SIMD3<Float>(-6144, -10240, 0))
        #expect(coordinate == CellCoordinate(x: -2, y: -3))
    }

    @Test
    func lowerBoundaryIsInsideTheCell() {
        // Cell (1,1) covers [4096, 8192) -- the lower edge belongs to it.
        let coordinate = CellGridManager.cellCoordinate(for: SIMD3<Float>(4096, 4096, 0))
        #expect(coordinate == CellCoordinate(x: 1, y: 1))
    }

    @Test
    func justBelowUpperBoundaryStaysInTheCell() {
        let coordinate = CellGridManager.cellCoordinate(for: SIMD3<Float>(8191.9, 8191.9, 0))
        #expect(coordinate == CellCoordinate(x: 1, y: 1))
    }

    @Test
    func negativeZeroBoundaryFallsInTheNegativeCell() {
        // Cell (-1,-1) covers [-4096, 0) -- values just under 0 belong there.
        let coordinate = CellGridManager.cellCoordinate(for: SIMD3<Float>(-0.001, -0.001, 0))
        #expect(coordinate == CellCoordinate(x: -1, y: -1))
    }

    // MARK: - desiredCells contents

    @Test
    func defaultRadiusProducesFiveByFiveGrid() {
        let manager = CellGridManager(initialPosition: SIMD3<Float>(0, 0, 0))
        let cells = manager.desiredCells
        #expect(cells.count == 25)
        for offsetX in -2 ... 2 {
            for offsetY in -2 ... 2 {
                #expect(cells.contains(CellCoordinate(x: Int32(offsetX), y: Int32(offsetY))))
            }
        }
    }

    @Test
    func desiredCellsAreCenteredOnCurrentCenter() {
        let position = SIMD3<Float>(cellSize * 5 + 100, cellSize * -3 + 100, 0)
        let manager = CellGridManager(initialPosition: position)
        #expect(manager.center == CellCoordinate(x: 5, y: -3))
        let cells = manager.desiredCells
        #expect(cells.contains(CellCoordinate(x: 5, y: -3)))
        #expect(cells.contains(CellCoordinate(x: 3, y: -5)))
        #expect(cells.contains(CellCoordinate(x: 7, y: -1)))
        #expect(!cells.contains(CellCoordinate(x: 2, y: -3)))
        #expect(!cells.contains(CellCoordinate(x: 5, y: -6)))
    }

    // MARK: - radius parameter

    @Test
    func zeroRadiusIsJustTheCenterCell() {
        let manager = CellGridManager(initialPosition: SIMD3<Float>(0, 0, 0), radius: 0)
        #expect(manager.desiredCells == [CellCoordinate(x: 0, y: 0)])
    }

    @Test
    func radiusOneProducesThreeByThreeGrid() {
        let manager = CellGridManager(initialPosition: SIMD3<Float>(0, 0, 0), radius: 1)
        #expect(manager.desiredCells.count == 9)
    }

    @Test
    func negativeRadiusClampsToZero() {
        let manager = CellGridManager(initialPosition: SIMD3<Float>(0, 0, 0), radius: -3)
        #expect(manager.radius == 0)
        #expect(manager.desiredCells.count == 1)
    }

    // MARK: - diff on one-cell move

    @Test
    func oneCellMoveLoadsLeadingEdgeAndUnloadsTrailingEdge() {
        var manager = CellGridManager(
            initialPosition: SIMD3<Float>(cellSize / 2, cellSize / 2, 0)
        )
        let loaded = manager.desiredCells
        #expect(manager.center == CellCoordinate(x: 0, y: 0))

        // Deep into cell (1,0): decisive crossing, well past the hysteresis
        // margin, single axis only.
        let moved = SIMD3<Float>(cellSize + cellSize / 2, cellSize / 2, 0)
        let diff = manager.update(cameraPosition: moved, loaded: loaded)

        #expect(manager.center == CellCoordinate(x: 1, y: 0))
        let expectedLoads = Set((-2 ... 2).map { CellCoordinate(x: 3, y: Int32($0)) })
        let expectedUnloads = Set((-2 ... 2).map { CellCoordinate(x: -2, y: Int32($0)) })
        #expect(diff?.loads == expectedLoads)
        #expect(diff?.unloads == expectedUnloads)
    }

    @Test
    func matchingLoadedSetAfterMoveReturnsNil() {
        var manager = CellGridManager(
            initialPosition: SIMD3<Float>(cellSize / 2, cellSize / 2, 0)
        )
        let moved = SIMD3<Float>(cellSize + cellSize / 2, cellSize / 2, 0)
        // Caller already fully caught up to the new desired grid.
        let alreadyLoaded = CellGridManager(initialPosition: moved).desiredCells
        let diff = manager.update(cameraPosition: moved, loaded: alreadyLoaded)
        #expect(diff == nil)
    }

    // MARK: - hysteresis: no thrash walking back and forth across a border

    @Test
    func oscillatingAcrossBorderWithinMarginDoesNotRecenterOrThrash() {
        var manager = CellGridManager(
            initialPosition: SIMD3<Float>(cellSize / 2, cellSize / 2, 0)
        )
        let loaded = manager.desiredCells
        #expect(manager.center == CellCoordinate(x: 0, y: 0))

        // Border between cell 0 and cell 1 sits at x = cellSize. Walk back
        // and forth within the hysteresis margin on either side -- never far
        // enough into cell 1 to justify recentering.
        let justOverBorder = SIMD3<Float>(cellSize + 50, cellSize / 2, 0)
        let justUnderBorder = SIMD3<Float>(cellSize - 50, cellSize / 2, 0)

        for _ in 0 ..< 5 {
            let overDiff = manager.update(cameraPosition: justOverBorder, loaded: loaded)
            #expect(manager.center == CellCoordinate(x: 0, y: 0))
            #expect(overDiff == nil)

            let underDiff = manager.update(cameraPosition: justUnderBorder, loaded: loaded)
            #expect(manager.center == CellCoordinate(x: 0, y: 0))
            #expect(underDiff == nil)
        }
    }

    @Test
    func decisiveCrossingPastMarginRecentersImmediately() {
        var manager = CellGridManager(
            initialPosition: SIMD3<Float>(cellSize / 2, cellSize / 2, 0)
        )
        let loaded = manager.desiredCells
        // 200 units past the border, past the 128-unit hysteresis margin.
        let wellInside = SIMD3<Float>(cellSize + 200, cellSize / 2, 0)
        let diff = manager.update(cameraPosition: wellInside, loaded: loaded)
        #expect(manager.center == CellCoordinate(x: 1, y: 0))
        #expect(diff != nil)
    }

    @Test
    func diagonalCornerCrossingNeedsMarginOnBothAxes() {
        var manager = CellGridManager(
            initialPosition: SIMD3<Float>(cellSize / 2, cellSize / 2, 0)
        )
        // Just past the corner on x, but not on y -- one axis short of
        // margin should hold the old center.
        let cornerShortOnY = SIMD3<Float>(cellSize + 200, cellSize + 50, 0)
        _ = manager.update(cameraPosition: cornerShortOnY, loaded: manager.desiredCells)
        #expect(manager.center == CellCoordinate(x: 0, y: 0))

        // Now past margin on both axes -- recenters to the diagonal cell.
        let cornerPastBoth = SIMD3<Float>(cellSize + 200, cellSize + 200, 0)
        _ = manager.update(cameraPosition: cornerPastBoth, loaded: manager.desiredCells)
        #expect(manager.center == CellCoordinate(x: 1, y: 1))
    }
}
