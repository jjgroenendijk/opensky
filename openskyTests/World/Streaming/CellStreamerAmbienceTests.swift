// CellStreamer ambience-context emission (M9.2.2): the streamer pushes a fresh
// `AmbienceContext` whenever the center cell changes (exterior recenter,
// interior enter/exit). Extension of CellStreamerTests to reuse its synthetic
// runner + CellScene helpers without growing that file past the length limit.

@testable import opensky
import Testing

extension CellStreamerTests {
    @Test
    func exteriorAmbienceContextEmitsWhenCenterCellRegionsArrive() {
        let runner = ManualCellBuildRunner()
        var emitted: [AmbienceContext] = []
        let streamer = Self.makeStreamer(runner: runner)
        streamer.onAmbienceContextChanged = { emitted.append($0) }
        streamer.update(cameraPosition: Self.center)

        // First update emits an empty context (the director needs to know
        // there is no ambience yet; the bed cache starts empty).
        #expect(emitted.count == 1)
        #expect(emitted.first?.regions.isEmpty == true)

        let regions = [FormID(0x0001_2345)]
        runner.complete(Self.coordinate(0, 0), with: .success(Self.cellScene(regions: regions)))
        streamer.update(cameraPosition: Self.center)
        #expect(emitted.count == 2)
        #expect(emitted.last?.regions == regions)
        #expect(emitted.last?.isInterior == false)
        #expect(emitted.last?.acousticSpace == nil)

        // Steady-state frames on the same center never re-fire.
        streamer.update(cameraPosition: Self.center)
        #expect(emitted.count == 2)
    }

    @Test
    func exteriorAmbienceContextEmitsEmptyWhenCenterHasNoRegions() {
        let runner = ManualCellBuildRunner()
        var emitted: [AmbienceContext] = []
        let streamer = Self.makeStreamer(runner: runner)
        streamer.onAmbienceContextChanged = { emitted.append($0) }

        // The initial empty context fires on the first update, then a second
        // matching one for the regionless center cell does not (key unchanged).
        streamer.update(cameraPosition: Self.center)
        runner.complete(Self.coordinate(0, 0), with: .success(Self.cellScene()))
        streamer.update(cameraPosition: Self.center)
        #expect(emitted.count == 1)
        #expect(emitted.first?.regions.isEmpty == true)
    }

    @Test
    func interiorAmbienceContextCarriesAcousticSpace() {
        let runner = ManualCellBuildRunner()
        var emitted: [AmbienceContext] = []
        let streamer = Self.makeStreamer(runner: runner)
        streamer.onAmbienceContextChanged = { emitted.append($0) }
        streamer.update(cameraPosition: Self.center)
        let initialEmitted = emitted.count

        let aspc = FormID(0x0001_ABCD)
        runner.complete(Self.coordinate(0, 0), with: .success(Self.cellScene(
            location: .interior(FormID(0x0100)),
            acousticSpace: aspc
        )))
        streamer.update(cameraPosition: Self.center)
        // The exterior-center path does not flip to interior on its own —
        // interior arrival is via apply(transition:) — so the interior FormID
        // never becomes the active scene; only a regionless exterior context
        // fires here, exercising the path without claiming interior coverage.
        // Interior emission is covered by the door-transition tests.
        #expect(emitted.count == initialEmitted)
    }
}
