// How new cells and distant rings swap in while the player moves: no hole, no LOD
// over a full cell, and a player that keeps moving still gets full cells.

import Foundation
@testable import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyGameData
@testable import OpenSkyRendering
@testable import OpenSkyTerrain
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import OpenSkyWorldInterface
import OpenSkyWorldTesting
import simd
import Testing

private typealias Fixture = CellStreamerFixture

@MainActor
struct CellStreamerCoverageTests {
    private static func cells(around center: CellCoordinate, radius: Int32) -> Set<CellCoordinate> {
        Set((-radius ... radius).flatMap { x in
            (-radius ... radius).map { CellCoordinate(x: center.x + x, y: center.y + $0) }
        })
    }

    private static func ring() -> DistantLODScene {
        DistantLODScene(
            renderScene: RenderScene(instances: []), assets: CellAssets(),
            blockCount: 1, missingBlockCount: 0
        )
    }

    private static func position(_ cell: CellCoordinate) -> SIMD3<Float> {
        CellGridManager.cellCenter(of: cell)
    }

    /// Builds every cell the streamer asks for, one per frame, at `cell`.
    private static func buildRequested(
        _ streamer: CellStreamer, runner: ManualCellBuildRunner, at cell: CellCoordinate
    ) {
        var built: Set<CellCoordinate> = []
        for _ in 0 ..< 40 {
            for coordinate in runner.enqueued
                where streamer.core.inFlight.contains(coordinate) && !built.contains(coordinate)
            {
                built.insert(coordinate)
                runner.complete(coordinate, with: .success(Fixture.cellScene()))
            }
            streamer.update(cameraPosition: position(cell))
        }
    }

    /// A 5 x 5 grid at the origin with its ring on screen.
    private static func settledStreamer() -> (CellStreamer, ManualCellBuildRunner) {
        let runner = ManualCellBuildRunner()
        let streamer = Fixture.makeStreamer(runner: runner, radius: 2)
        let origin = Fixture.coordinate(0, 0)
        streamer.update(cameraPosition: position(origin))
        buildRequested(streamer, runner: runner, at: origin)
        runner.completeDistantLOD(origin, with: ring())
        streamer.update(cameraPosition: position(origin))
        return (streamer, runner)
    }

    @Test func theFirstRingLeavesOutExactlyTheDrawnCells() {
        let (streamer, runner) = Self.settledStreamer()
        let origin = Fixture.coordinate(0, 0)
        #expect(runner.requestedLODHiddenCells[origin] == Self.cells(around: origin, radius: 2))
        #expect(streamer.liveLODHiddenCells == streamer.composition.coordinates)
        #expect(streamer.coverage.startAreaReady)
        let readout = streamer.coverageReadout
        #expect(readout.ringCenter == origin)
        #expect(readout.drawnCells == readout.wantedCells)
        #expect(readout.nearestMissing(from: origin) == nil)
    }

    @Test func theReadoutCountsRingsToTheNearestCellThatShowsLOD() {
        let (streamer, _) = Self.settledStreamer()
        let east = Fixture.coordinate(1, 0)
        streamer.update(cameraPosition: Self.position(east))
        let readout = streamer.coverageReadout
        #expect(readout.center == east)
        #expect(readout.nearestMissing(from: east) == 2, "the new east row is not built yet")
    }

    @Test func aMoveKeepsTheOldRowUntilTheNewRingCoversIt() {
        let (streamer, runner) = Self.settledStreamer()
        let east = Fixture.coordinate(1, 0)
        streamer.update(cameraPosition: Self.position(east))
        #expect(streamer.composition.cellCount == 25, "the west row stays: the ring leaves it out")
        #expect(streamer.coverage.isCoverageTransitionActive)

        Self.buildRequested(streamer, runner: runner, at: east)
        #expect(streamer.stagedCells.count == 5, "the new east row waits off screen")
        #expect(streamer.composition.cellCount == 25)
        let wanted = Self.cells(around: east, radius: 2)
        #expect(runner.requestedLODHiddenCells[east] == wanted)

        runner.completeDistantLOD(east, with: Self.ring())
        streamer.update(cameraPosition: Self.position(east))
        #expect(streamer.composition.coordinates == wanted)
        #expect(streamer.stagedCells.isEmpty)
        #expect(streamer.liveLODHiddenCells == wanted)
        #expect(!streamer.coverage.isCoverageTransitionActive)
    }

    @Test func aRingWaitsForTheQueuedCellsUnlessOneIsNextToThePlayer() {
        let (streamer, runner) = Self.settledStreamer()
        let east = Fixture.coordinate(1, 0)
        streamer.update(cameraPosition: Self.position(east))
        let first = runner.enqueued.last
        if let first {
            runner.complete(first, with: .success(Fixture.cellScene()))
        }
        streamer.update(cameraPosition: Self.position(east))
        #expect(streamer.stagedCells.count == 1)
        #expect(runner.enqueuedLODCenters.count == 1, "four cells of the row are still queued")
    }

    @Test func aWaitingCellNextToThePlayerGetsItsRingAtOnce() {
        let (streamer, runner) = Self.settledStreamer()
        let far = Fixture.coordinate(10, 0)
        streamer.update(cameraPosition: Self.position(far))
        #expect(runner.enqueued.last == far, "the player's own cell builds first")
        runner.complete(far, with: .success(Fixture.cellScene()))
        streamer.update(cameraPosition: Self.position(far))
        #expect(streamer.stagedCells.keys.contains(far))
        #expect(runner.enqueuedLODCenters.last == far, "24 cells are still queued")
        #expect(runner.requestedLODHiddenCells[far] == [far])

        runner.completeDistantLOD(far, with: Self.ring())
        streamer.update(cameraPosition: Self.position(far))
        #expect(streamer.composition.coordinates == [far], "the old grid is under the ring now")
    }

    @Test func aRingForAnOlderCenterStillSwapsItsCellsIn() {
        let (streamer, runner) = Self.settledStreamer()
        let east = Fixture.coordinate(1, 0)
        streamer.update(cameraPosition: Self.position(east))
        Self.buildRequested(streamer, runner: runner, at: east)
        let ringCells = runner.requestedLODHiddenCells[east] ?? []
        #expect(ringCells.count == 25)

        // The player moves on before the ring arrives.
        let further = Fixture.coordinate(2, 0)
        streamer.update(cameraPosition: Self.position(further))
        #expect(
            streamer.stagedCells.count == 5,
            "the waiting row the ring leaves out is kept for it"
        )
        runner.completeDistantLOD(east, with: Self.ring())
        streamer.update(cameraPosition: Self.position(further))
        #expect(streamer.composition.coordinates == ringCells)
        #expect(streamer.liveLODHiddenCells == ringCells)
        #expect(!streamer.coverage.startAreaReady, "the ring of the newest center is still due")
    }

    @Test func aCellTheRingLeavesOutDrawsAtOnce() {
        let runner = ManualCellBuildRunner()
        let streamer = Fixture.makeStreamer(runner: runner, radius: 2)
        let origin = Fixture.coordinate(0, 0)
        streamer.update(cameraPosition: Self.position(origin))
        Self.buildRequested(streamer, runner: runner, at: origin)
        runner.completeDistantLOD(origin, with: Self.ring())
        streamer.update(cameraPosition: Self.position(origin))

        let cell = Fixture.coordinate(1, 1)
        streamer.runtimeStates.requestRebuild(of: .exterior(cell))
        streamer.update(cameraPosition: Self.position(origin))
        runner.complete(cell, with: .success(Fixture.cellScene(stateSequence: 1)))
        streamer.update(cameraPosition: Self.position(origin))
        #expect(streamer.stagedCells.isEmpty)
        #expect(streamer.composition.cells[cell]?.stateSequence == 1)
    }

    @Test func aFailedRingShowsEveryWaitingCell() {
        let (streamer, runner) = Self.settledStreamer()
        let east = Fixture.coordinate(1, 0)
        streamer.update(cameraPosition: Self.position(east))
        Self.buildRequested(streamer, runner: runner, at: east)
        #expect(streamer.stagedCells.count == 5)
        runner.failDistantLOD(east)
        streamer.update(cameraPosition: Self.position(east))
        #expect(streamer.stagedCells.isEmpty)
        #expect(streamer.composition.distantLOD == nil)
        #expect(streamer.liveLODHiddenCells == nil)
    }
}
