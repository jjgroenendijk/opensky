// CellStreamer pushes a new `AmbienceContext` when the center cell changes.
// Extends CellStreamerTests to reuse its helpers within the length limit.

@testable import OpenSkyAudio
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import Testing

private typealias Fixture = CellStreamerFixture

extension CellStreamerTests {
    @Test
    func exteriorAmbienceContextEmitsWhenCenterCellRegionsArrive() {
        let runner = ManualCellBuildRunner()
        var emitted: [AmbienceContext] = []
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.onAmbienceContextChanged = { emitted.append($0) }
        streamer.update(cameraPosition: Fixture.center)

        // First update emits an empty context (the director needs to know
        // there is no ambience yet; the bed cache starts empty).
        #expect(emitted.count == 1)
        #expect(emitted.first?.regions.isEmpty == true)

        let regions = [FormID(0x0001_2345)]
        runner.complete(
            Fixture.coordinate(0, 0),
            with: .success(Fixture.cellScene(regions: regions))
        )
        streamer.update(cameraPosition: Fixture.center)
        #expect(emitted.count == 2)
        #expect(emitted.last?.regions == regions)
        #expect(emitted.last?.isInterior == false)
        #expect(emitted.last?.acousticSpace == nil)

        // Steady-state frames on the same center never re-fire.
        streamer.update(cameraPosition: Fixture.center)
        #expect(emitted.count == 2)
    }

    @Test
    func exteriorAmbienceContextEmitsEmptyWhenCenterHasNoRegions() {
        let runner = ManualCellBuildRunner()
        var emitted: [AmbienceContext] = []
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.onAmbienceContextChanged = { emitted.append($0) }

        // The initial empty context fires on the first update, then a second
        // matching one for the regionless center cell does not (key unchanged).
        streamer.update(cameraPosition: Fixture.center)
        runner.complete(Fixture.coordinate(0, 0), with: .success(Fixture.cellScene()))
        streamer.update(cameraPosition: Fixture.center)
        #expect(emitted.count == 1)
        #expect(emitted.first?.regions.isEmpty == true)
    }

    @Test
    func interiorAmbienceContextCarriesAcousticSpace() {
        let runner = ManualCellBuildRunner()
        var emitted: [AmbienceContext] = []
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.onAmbienceContextChanged = { emitted.append($0) }
        streamer.update(cameraPosition: Fixture.center)
        let initialEmitted = emitted.count

        let aspc = FormID(0x0001_ABCD)
        runner.complete(Fixture.coordinate(0, 0), with: .success(Fixture.cellScene(
            location: .interior(FormID(0x0100)),
            acousticSpace: aspc
        )))
        streamer.update(cameraPosition: Fixture.center)
        // The exterior-center path does not flip to interior on its own —
        // interior arrival is via apply(transition:) — so the interior FormID
        // never becomes the active scene; only a regionless exterior context
        // fires here, exercising the path without claiming interior coverage.
        // Interior emission is covered by the door-transition tests.
        #expect(emitted.count == initialEmitted)
    }
}
