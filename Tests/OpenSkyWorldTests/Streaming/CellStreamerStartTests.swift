// CellStreamer before the player picks a start: a held streamer loads nothing,
// and a moved start loads at the move and not at the launch cell.

import Foundation
@testable import OpenSkyCells
@testable import OpenSkyRendering
import OpenSkyTerrain
import OpenSkyWorld
import OpenSkyWorldFixtures
import OpenSkyWorldTesting
import simd
import Testing

private typealias Fixture = CellStreamerFixture

@MainActor
struct CellStreamerStartTests {
    @Test
    func aHeldStreamerLoadsNothing() {
        let runner = ManualCellBuildRunner()
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.isHeld = true
        streamer.update(cameraPosition: Fixture.center)
        streamer.update(cameraPosition: Fixture.center)
        #expect(runner.enqueued.isEmpty)
        #expect(runner.enqueuedLODCenters.isEmpty)

        streamer.isHeld = false
        streamer.update(cameraPosition: Fixture.center)
        #expect(runner.enqueued.first == Fixture.coordinate(0, 0))
    }

    @Test
    func aMovedStartLoadsThereAndKeepsTheCamera() {
        let runner = ManualCellBuildRunner()
        var framed: [SceneCamera] = []
        let streamer = Fixture.makeStreamer(runner: runner) { _, camera in
            if let camera {
                framed.append(camera)
            }
        }
        let start = CellGridManager.cellCenter(of: Fixture.coordinate(5, 5))
        streamer.isHeld = true
        streamer.moveStart(to: start)
        streamer.isHeld = false
        streamer.update(cameraPosition: start)
        #expect(runner.enqueued.first == Fixture.coordinate(5, 5))

        runner.complete(Fixture.coordinate(5, 5), with: .success(Fixture.cellScene()))
        streamer.update(cameraPosition: start)
        #expect(streamer.composedCellCount == 1)
        #expect(framed.isEmpty)
    }

    @Test
    func aStartDoesNotMoveOnceACellFramedTheView() {
        let runner = ManualCellBuildRunner()
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.update(cameraPosition: Fixture.center)
        runner.complete(Fixture.coordinate(0, 0), with: .success(Fixture.cellScene()))
        streamer.update(cameraPosition: Fixture.center)
        streamer.moveStart(to: CellGridManager.cellCenter(of: Fixture.coordinate(5, 5)))
        #expect(streamer.composedCellCount == 1)
        #expect(streamer.grid.center == Fixture.coordinate(0, 0))
    }
}
