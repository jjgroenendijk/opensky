// Live XCLR region feed (M7.2.3): the streamer pushes the current exterior
// center cell's REGN FormIDs into `onCenterRegionsChanged` (wired to
// WeatherSystem.setRegions in the app) whenever they change. Extension of
// CellStreamerTests to reuse its synthetic runner + CellScene helpers without
// growing that file past the length limit. No Metal, no game data.

@testable import OpenSkyFormatsESM
@testable import OpenSkyWorld
import OpenSkyWorldTesting
import Testing

private typealias Fixture = CellStreamerFixture

extension CellStreamerTests {
    @Test
    func centerCellRegionsEmitOnceToWeatherFeed() {
        let runner = ManualCellBuildRunner()
        var emitted: [[FormID]] = []
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.onCenterRegionsChanged = { emitted.append($0) }
        streamer.update(cameraPosition: Fixture.center)

        // Before the center cell is resident, nothing is pushed (a loading gap
        // must not drop region weighting).
        #expect(emitted.isEmpty)

        let regions = [FormID(0x0001_2345), FormID(0x0006_789A)]
        runner.complete(
            Fixture.coordinate(0, 0),
            with: .success(Fixture.cellScene(regions: regions))
        )
        streamer.update(cameraPosition: Fixture.center)
        #expect(emitted == [regions], "center cell regions were not pushed once")

        // Steady-state frames on the same center never re-fire the set.
        streamer.update(cameraPosition: Fixture.center)
        streamer.update(cameraPosition: Fixture.center)
        #expect(emitted == [regions], "unchanged center refired the region feed")
    }

    @Test
    func regionlessCenterCellEmitsEmptySet() {
        let runner = ManualCellBuildRunner()
        var emitted: [[FormID]] = []
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.onCenterRegionsChanged = { emitted.append($0) }
        streamer.update(cameraPosition: Fixture.center)

        runner.complete(Fixture.coordinate(0, 0), with: .success(Fixture.cellScene()))
        streamer.update(cameraPosition: Fixture.center)
        #expect(emitted == [[]], "a center cell with no XCLR must push an empty set")
    }
}
