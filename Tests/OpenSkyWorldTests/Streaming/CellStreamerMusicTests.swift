// CellStreamer pushes a new `MusicContext` when the center cell's selection
// identity changes. Extends CellStreamerTests within the length limit.

@testable import OpenSkyAudio
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import Testing

private typealias Fixture = CellStreamerFixture

extension CellStreamerTests {
    @Test
    func exteriorMusicContextEmitsWhenTheCenterCellArrives() {
        let runner = ManualCellBuildRunner()
        var emitted: [MusicContext] = []
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.onMusicContextChanged = { emitted.append($0) }
        streamer.update(cameraPosition: Fixture.center)

        // First update emits the empty context: the director needs to know
        // there is no music yet rather than inferring it from silence.
        #expect(emitted.count == 1)
        #expect(emitted.first?.cellMusicType == nil)

        runner.complete(Fixture.coordinate(0, 0), with: .success(Fixture.cellScene(
            regions: [FormID(0x200)],
            musicType: FormID(0x20),
            worldspaceMusicType: FormID(0x30)
        )))
        streamer.update(cameraPosition: Fixture.center)
        #expect(emitted.count == 2)
        #expect(emitted.last?.cellMusicType == FormID(0x20))
        #expect(emitted.last?.regions == [FormID(0x200)])
        #expect(emitted.last?.worldspaceMusicType == FormID(0x30))
        #expect(emitted.last?.isInterior == false)

        // Steady-state frames on the same center never re-fire.
        streamer.update(cameraPosition: Fixture.center)
        streamer.update(cameraPosition: Fixture.center)
        #expect(emitted.count == 2)
    }

    @Test
    func locationMusicIsLookedUpOnceWhenTheCenterCellArrives() {
        let runner = ManualCellBuildRunner()
        var emitted: [MusicContext] = []
        var lookups = 0
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.onMusicContextChanged = { emitted.append($0) }
        streamer.musicFeed.locationMusicType = { _ in
            lookups += 1
            return FormID(0x50)
        }
        streamer.update(cameraPosition: Fixture.center)
        #expect(lookups == 0)
        #expect(emitted.last?.locationMusicType == nil)

        runner.complete(Fixture.coordinate(0, 0), with: .success(Fixture.cellScene()))
        streamer.update(cameraPosition: Fixture.center)
        streamer.update(cameraPosition: Fixture.center)
        #expect(lookups == 1)
        #expect(emitted.count == 2)
        #expect(emitted.last?.locationMusicType == FormID(0x50))
    }

    /// A cell with no music emits once more when it arrives, because only then can
    /// its location be read. The context is the same, so the music does not change.
    @Test
    func musiclessCenterCellReEmitsTheSameContext() {
        let runner = ManualCellBuildRunner()
        var emitted: [MusicContext] = []
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.onMusicContextChanged = { emitted.append($0) }
        streamer.update(cameraPosition: Fixture.center)
        runner.complete(Fixture.coordinate(0, 0), with: .success(Fixture.cellScene()))
        streamer.update(cameraPosition: Fixture.center)
        streamer.update(cameraPosition: Fixture.center)
        #expect(emitted.count == 2)
        #expect(emitted.last == emitted.first)
    }

    @Test
    func invalidateForcesAReEmitOfTheSameContext() {
        let runner = ManualCellBuildRunner()
        var emitted: [MusicContext] = []
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.onMusicContextChanged = { emitted.append($0) }
        streamer.update(cameraPosition: Fixture.center)
        #expect(emitted.count == 1)

        streamer.invalidateMusicContext()
        streamer.update(cameraPosition: Fixture.center)
        #expect(emitted.count == 2)
        #expect(emitted.last == emitted.first)
    }

    @Test
    func interiorTransitionEmitsTheInteriorMusicContext() {
        let runner = ManualCellBuildRunner()
        var emitted: [MusicContext] = []
        let streamer = Fixture.makeStreamer(runner: runner)
        streamer.onMusicContextChanged = { emitted.append($0) }
        streamer.update(cameraPosition: Fixture.center)
        let beforeEntering = emitted.count

        let interior = Fixture.cellScene(
            location: .interior(FormID(0x138CA)), musicType: FormID(0x40)
        )
        streamer.apply(transition: DoorTransition(
            sourceDoor: FormID(0x10),
            destinationDoor: FormID(0x20),
            destinationPlacement: PlacedReference.Placement(
                position: SIMD3(100, 200, 300), rotation: .zero
            ),
            scene: interior
        ))
        #expect(emitted.count == beforeEntering + 1)
        #expect(emitted.last?.isInterior == true)
        #expect(emitted.last?.cellMusicType == FormID(0x40))
        #expect(emitted.last?.regions.isEmpty == true)
        #expect(emitted.last?.worldspaceMusicType == nil)
        #expect(emitted.last?.cellIdentity == 0x138CA)
    }
}
