// The main menu movie on the user's install: `startmenu.swf` still builds the
// rows `TitleMenuMovieBridge` measured, and the keys reach the engine calls. Load
// asks for the character list, and a picked character asks for its saves.

import Foundation
@testable import OpenSkyFormatsSWF
@testable import OpenSkyGameData
@testable import OpenSkyMenus
import Testing

struct TitleMenuMovieRealDataTests {
    @MainActor
    private final class Requests {
        var seen: [TitleMenuMovieBridge.Request] = []
        var loadCalls: [TitleMenuLoadBridge.Request] = []
    }

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot)) @MainActor
    func theMainRowsBuildAndTheKeysReachTheEngine() throws {
        let (runtime, requests) = try startMovie()
        #expect(TitleMenuMovieBridge.entryLabels(runtime: runtime)
            == ["$CONTINUE", "$NEW", "$LOAD", "$CREDITS", "$QUIT"])
        #expect(TitleMenuMovieBridge.currentState(runtime: runtime) == "Main")

        let keys: [MenuInputEvent] = [
            .button(.accept), .move(.down), .button(.accept), .move(.down),
            .button(.accept)
        ]
        press(keys, runtime: runtime)
        #expect(requests.seen == [.resume, .new])
        #expect(requests.loadCalls.first == .characters)
        TitleMenuLoadBridge.fillCharacters(["Ada"], runtime: runtime)
        for _ in 0 ..< TitleMenuMovieBridge.activationTicks {
            runtime.advance()
        }
        TitleMenuMovieBridge.followStateFocus(runtime: runtime)
        #expect(TitleMenuMovieBridge.currentState(runtime: runtime) == "CharacterSelection")
        press([.button(.accept)], runtime: runtime)
        #expect(requests.loadCalls.contains(.characterSelected))
        TitleMenuMovieBridge.returnToMain(runtime: runtime)
        #expect(TitleMenuMovieBridge.currentState(runtime: runtime) == "Main")
        let quit: [MenuInputEvent] = [
            .move(.down),
            .move(.down),
            .button(.accept),
            .button(.accept)
        ]
        press(quit, runtime: runtime)
        #expect(requests.seen.last == .quit)
    }

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot)) @MainActor
    func theRowUnderTheCursorHighlightsAndAClickPicksIt() throws {
        let (runtime, requests) = try startMovie()

        // A view the size of the stage, so a view point is a stage pixel.
        let frame = runtime.movie.frameSize
        let size = SIMD2(Float(frame.xMax - frame.xMin), Float(frame.yMax - frame.yMin)) / 20
        var rowPoints: [Int: SIMD2<Float>] = [:]
        for column in stride(from: Float(0.05), through: 0.95, by: 0.05) {
            for pixelY in stride(from: Float(0), to: size.y, by: 4) {
                let point = SIMD2(size.x * column, pixelY)
                TitleMenuMovieBridge.handle(
                    MenuPointerEvent(.moved, location: point, viewSize: size), runtime: runtime
                )
                if let index = TitleMenuMovieBridge.selectedIndex(runtime: runtime) {
                    rowPoints[index] = rowPoints[index] ?? point
                }
            }
        }
        #expect(Set(rowPoints.keys) == Set(0 ..< 5))
        #expect(requests.seen.isEmpty)

        try click(#require(rowPoints[1]), size: size, runtime: runtime)
        #expect(requests.seen == [.new])
        try click(#require(rowPoints[2]), size: size, runtime: runtime)
        #expect(requests.loadCalls.first == .characters)
    }

    @MainActor
    private func click(_ point: SIMD2<Float>, size: SIMD2<Float>, runtime: SWFMovieRuntime) {
        for phase in [MenuPointerEvent.Phase.moved, .pressed, .released] {
            TitleMenuMovieBridge.handle(
                MenuPointerEvent(phase, location: point, viewSize: size), runtime: runtime
            )
        }
        advance(runtime)
    }

    @MainActor
    private func startMovie() throws -> (SWFMovieRuntime, Requests) {
        let root = try #require(RealDataEnvironment.dataRoot)
        let loader = SWFMovieLoader(fileSystem: VirtualFileSystem(root: root))
        let runtime = try SWFMovieRuntime(
            movieScene: loader.load(path: TitleMenuMovieBridge.moviePath)
        )
        let requests = Requests()
        TitleMenuMovieBridge.prepare(runtime: runtime) { requests.seen.append($0) }
        TitleMenuLoadBridge.prepare(runtime: runtime) { requests.loadCalls.append($0.request) }
        runtime.start()
        TitleMenuMovieBridge.activate(runtime: runtime, hasSaves: true, version: "OpenSky")
        advance(runtime)
        return (runtime, requests)
    }

    @MainActor
    private func advance(_ runtime: SWFMovieRuntime) {
        for _ in 0 ..< TitleMenuMovieBridge.activationTicks {
            runtime.advance()
        }
    }

    /// The confirm question plays an animation, so each key gets frames.
    @MainActor
    private func press(_ events: [MenuInputEvent], runtime: SWFMovieRuntime) {
        for event in events {
            TitleMenuMovieBridge.handle(event, runtime: runtime)
            for _ in 0 ..< TitleMenuMovieBridge.activationTicks {
                runtime.advance()
            }
        }
    }
}
