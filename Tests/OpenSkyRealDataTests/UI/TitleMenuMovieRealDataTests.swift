// The main menu movie on the user's install: `startmenu.swf` still builds the
// rows `TitleMenuMovieBridge` measured, and the keys reach the engine calls.

import Foundation
@testable import OpenSkyFormatsSWF
@testable import OpenSkyGameData
@testable import OpenSkyMenus
import Testing

struct TitleMenuMovieRealDataTests {
    @MainActor
    private final class Requests {
        var seen: [TitleMenuMovieBridge.Request] = []
    }

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot)) @MainActor
    func theMainRowsBuildAndTheKeysReachTheEngine() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let loader = SWFMovieLoader(fileSystem: VirtualFileSystem(root: root))
        let runtime = try SWFMovieRuntime(
            movieScene: loader.load(path: TitleMenuMovieBridge.moviePath)
        )
        let requests = Requests()
        TitleMenuMovieBridge.prepare(runtime: runtime) { requests.seen.append($0) }
        runtime.start()
        TitleMenuMovieBridge.activate(runtime: runtime, hasSaves: true, version: "OpenSky")
        for _ in 0 ..< TitleMenuMovieBridge.activationTicks {
            runtime.advance()
        }
        #expect(TitleMenuMovieBridge.entryLabels(runtime: runtime)
            == ["$CONTINUE", "$NEW", "$LOAD", "$CREDITS", "$QUIT"])
        #expect(TitleMenuMovieBridge.currentState(runtime: runtime) == "Main")

        let keys: [MenuInputEvent] = [
            .button(.accept), .move(.down), .button(.accept), .move(.down),
            .button(.accept)
        ]
        press(keys, runtime: runtime)
        #expect(requests.seen == [.resume, .new, .load])
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
