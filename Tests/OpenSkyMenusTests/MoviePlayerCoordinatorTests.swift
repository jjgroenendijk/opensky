// The movie player: the clock starts at the first picture, a late decode catches up
// to the frame due, the movie ends on time, and only an interruptible one skips.

import Foundation
import OpenSkyAudio
import OpenSkyFormatsCore
@testable import OpenSkyGameData
@testable import OpenSkyMenus
import Testing

private final class FakeMovieWorld: MoviePlayerWorld {
    var movieFiles: (any GameFileSource)? {
        nil
    }

    var shown: [Int?] = []
    var soundStarts = 0
    var soundEnds = 0

    func showMoviePicture(_ picture: MoviePicture?, letterbox _: Bool) {
        shown.append(picture.map { Int($0.luma[0]) })
    }

    func startMovieSound(_: DecodedAudio?, request _: MovieRequest) {
        soundStarts += 1
    }

    func endMovieSound() {
        soundEnds += 1
    }
}

/// Each picture's first luma byte is its frame number.
private struct CountingFrames: MovieFrameSource {
    let clock: MovieClock
    var failingFrame: Int?

    func picture(ofFrame index: Int) throws -> MoviePicture? {
        if index == failingFrame {
            throw AssetLoadFailure(reason: "broken frame")
        }
        return MoviePicture(
            width: 2, height: 2, luma: Data([UInt8(index), 0, 0, 0]), chromaBlue: Data([0]),
            chromaRed: Data([0]), isFullRange: false
        )
    }
}

@MainActor
struct MoviePlayerCoordinatorTests {
    private let menuMode = MenuModeController()
    private let world = FakeMovieWorld()

    private func player(
        frames: Int = 10, interruptible: Bool = false, failingFrame: Int? = nil,
        onEnd: @escaping (MovieOutcome) -> Void = { _ in }
    ) -> MoviePlayerCoordinator {
        let player = MoviePlayerCoordinator(menuMode: menuMode, world: world) { frames in
            ImmediateAssetLoadWorker { try frames.picture(ofFrame: $0) }
        }
        let request = MovieRequest(fileName: "Test.bik", interruptible: interruptible)
        let source = CountingFrames(
            clock: MovieClock(framesPerSecond: 10, frameCount: frames), failingFrame: failingFrame
        )
        #expect(player.begin(request, onEnd: onEnd))
        player.opened(.success(LoadedMovie(frames: source, sound: nil)), for: request)
        return player
    }

    @Test func theFirstPictureStartsTheClockAndTheSound() {
        let player = player()
        #expect(menuMode.topMenu == MoviePlayerCoordinator.identifier)
        player.tick(now: 100)
        #expect(world.shown == [0])
        #expect(world.soundStarts == 1)
        player.tick(now: 100.25)
        #expect(world.shown == [0, 2])
        #expect(player.readout.frame == 2)
    }

    @Test func aLateDecodeShowsTheNewestReadyFrameThenCatchesUp() {
        let player = player()
        player.tick(now: 0)
        // Frames 0 to 3 were asked for; frame 5 is due, so 3 shows.
        player.tick(now: 0.5)
        #expect(world.shown.last == 3)
        player.tick(now: 0.6)
        #expect(world.shown.last == 6)
    }

    @Test func theMovieEndsAfterItsLastFrame() {
        var outcome: MovieOutcome?
        let player = player(onEnd: { outcome = $0 })
        player.tick(now: 0)
        player.tick(now: 1.0)
        #expect(outcome == .finished)
        #expect(world.shown.last == .some(nil))
        #expect(world.soundEnds == 1)
        #expect(menuMode.topMenu == nil)
        #expect(!player.isPlaying)
        #expect(player.readout.lastOutcome == .finished)
    }

    @Test func onlyAnInterruptibleMovieSkipsOnAKey() {
        let fixed = player()
        fixed.route(.button(.cancel))
        #expect(fixed.isPlaying)
        #expect(fixed.skip(force: true))
        #expect(!fixed.isPlaying)

        var outcome: MovieOutcome?
        let skippable = player(interruptible: true, onEnd: { outcome = $0 })
        skippable.route(.button(.cancel))
        #expect(outcome == .skipped)
    }

    @Test func aDecodeFailureEndsTheMovie() {
        var outcome: MovieOutcome?
        let player = player(failingFrame: 0, onEnd: { outcome = $0 })
        player.tick(now: 0)
        #expect(outcome == .failed("broken frame"))
        #expect(menuMode.topMenu == nil)
    }

    @Test func aSecondMovieWaitsForTheFirst() {
        let player = player()
        #expect(!player.begin(MovieRequest(fileName: "Other.bik"), onEnd: { _ in }))
    }

    @Test func thePathFallsUnderTheVideoFolder() {
        #expect(MovieRequest(fileName: "BGS_Logo.bik").path == "video\\BGS_Logo.bik")
        #expect(MovieRequest(fileName: "Video/Intro.bik").path == "Video\\Intro.bik")
    }
}
