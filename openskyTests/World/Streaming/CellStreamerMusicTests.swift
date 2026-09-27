// CellStreamer music-context emission (M9.2.3): the streamer pushes a fresh
// `MusicContext` whenever the selection identity of the center cell changes.
// Extension of CellStreamerTests to reuse its synthetic runner + CellScene
// helpers without growing that file past the length limit.

@testable import opensky
import Testing

extension CellStreamerTests {
    @Test
    func exteriorMusicContextEmitsWhenTheCenterCellArrives() {
        let runner = ManualCellBuildRunner()
        var emitted: [MusicContext] = []
        let streamer = Self.makeStreamer(runner: runner)
        streamer.onMusicContextChanged = { emitted.append($0) }
        streamer.update(cameraPosition: Self.center)

        // First update emits the empty context: the director needs to know
        // there is no music yet rather than inferring it from silence.
        #expect(emitted.count == 1)
        #expect(emitted.first?.cellMusicType == nil)

        runner.complete(Self.coordinate(0, 0), with: .success(Self.cellScene(
            regions: [FormID(0x200)],
            musicType: FormID(0x20),
            worldspaceMusicType: FormID(0x30)
        )))
        streamer.update(cameraPosition: Self.center)
        #expect(emitted.count == 2)
        #expect(emitted.last?.cellMusicType == FormID(0x20))
        #expect(emitted.last?.regions == [FormID(0x200)])
        #expect(emitted.last?.worldspaceMusicType == FormID(0x30))
        #expect(emitted.last?.isInterior == false)

        // Steady-state frames on the same center never re-fire.
        streamer.update(cameraPosition: Self.center)
        streamer.update(cameraPosition: Self.center)
        #expect(emitted.count == 2)
    }

    /// A cell that authors no music at all leaves the key unchanged, so the
    /// initial empty emission is not repeated.
    @Test
    func musiclessCenterCellDoesNotReEmit() {
        let runner = ManualCellBuildRunner()
        var emitted: [MusicContext] = []
        let streamer = Self.makeStreamer(runner: runner)
        streamer.onMusicContextChanged = { emitted.append($0) }
        streamer.update(cameraPosition: Self.center)
        runner.complete(Self.coordinate(0, 0), with: .success(Self.cellScene()))
        streamer.update(cameraPosition: Self.center)
        #expect(emitted.count == 1)
    }

    @Test
    func invalidateForcesAReEmitOfTheSameContext() {
        let runner = ManualCellBuildRunner()
        var emitted: [MusicContext] = []
        let streamer = Self.makeStreamer(runner: runner)
        streamer.onMusicContextChanged = { emitted.append($0) }
        streamer.update(cameraPosition: Self.center)
        #expect(emitted.count == 1)

        streamer.invalidateMusicContext()
        streamer.update(cameraPosition: Self.center)
        #expect(emitted.count == 2)
        #expect(emitted.last == emitted.first)
    }

    @Test
    func interiorTransitionEmitsTheInteriorMusicContext() {
        let runner = ManualCellBuildRunner()
        var emitted: [MusicContext] = []
        let streamer = Self.makeStreamer(runner: runner)
        streamer.onMusicContextChanged = { emitted.append($0) }
        streamer.update(cameraPosition: Self.center)
        let beforeEntering = emitted.count

        let interior = Self.cellScene(
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
