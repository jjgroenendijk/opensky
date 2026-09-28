// Live XCLR region feed (M7.2.3): the streamer pushes the current exterior
// center cell's REGN FormIDs into `onCenterRegionsChanged` (wired to
// WeatherSystem.setRegions in the app) whenever they change. Extension of
// CellStreamerTests to reuse its synthetic runner + CellScene helpers without
// growing that file past the length limit. No Metal, no game data.

@testable import opensky
import Testing

extension CellStreamerTests {
    @Test
    func centerCellRegionsEmitOnceToWeatherFeed() {
        let runner = ManualCellBuildRunner()
        var emitted: [[FormID]] = []
        let streamer = Self.makeStreamer(runner: runner)
        streamer.onCenterRegionsChanged = { emitted.append($0) }
        streamer.update(cameraPosition: Self.center)

        // Before the center cell is resident, nothing is pushed (a loading gap
        // must not drop region weighting).
        #expect(emitted.isEmpty)

        let regions = [FormID(0x0001_2345), FormID(0x0006_789A)]
        runner.complete(Self.coordinate(0, 0), with: .success(Self.cellScene(regions: regions)))
        streamer.update(cameraPosition: Self.center)
        #expect(emitted == [regions], "center cell regions were not pushed once")

        // Steady-state frames on the same center never re-fire the set.
        streamer.update(cameraPosition: Self.center)
        streamer.update(cameraPosition: Self.center)
        #expect(emitted == [regions], "unchanged center refired the region feed")
    }

    @Test
    func regionlessCenterCellEmitsEmptySet() {
        let runner = ManualCellBuildRunner()
        var emitted: [[FormID]] = []
        let streamer = Self.makeStreamer(runner: runner)
        streamer.onCenterRegionsChanged = { emitted.append($0) }
        streamer.update(cameraPosition: Self.center)

        runner.complete(Self.coordinate(0, 0), with: .success(Self.cellScene()))
        streamer.update(cameraPosition: Self.center)
        #expect(emitted == [[]], "a center cell with no XCLR must push an empty set")
    }
}
