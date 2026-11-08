// MenuMovieSession: the layer hand-off and the failure readouts, without a movie.

import OpenSkyEngineTesting
@testable import OpenSkyMenus
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.gpu), .unlessPlanSkips(.gpu))
@MainActor
struct MenuMovieSessionTests {
    private static let canvas = OffscreenCanvas(width: 64, height: 64, shaders: .packageFixture)
    private static let movie = MenuMovie(path: "interface/missing.swf")

    @Test func noGameDataLeavesTheLayerWithTheHUD() {
        let movies = SWFMovieSource()
        let session = MenuMovieSession(
            movies: movies, hud: HUDCoordinator(movies: movies), label: "test"
        ) { nil }
        session.start(Self.movie)
        #expect(!session.isLoaded)
        #expect(!session.holdsLayer)
        #expect(session.error == "No game data located.")
    }

    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device))
    func aMissingMovieKeepsTheLayerUntilStop() throws {
        let renderer = try Self.canvas.makeRenderer()
        let movies = SWFMovieSource(fileSystem: InMemoryFileSource(), loadsImmediately: true)
        let session = MenuMovieSession(
            movies: movies, hud: HUDCoordinator(movies: movies), label: "test"
        ) { renderer }
        session.start(Self.movie)
        #expect(session.holdsLayer)
        #expect(!session.isLoaded)
        #expect(session.error != nil)
        #expect(session.path == Self.movie.path)
        session.stop()
        #expect(!session.holdsLayer)
        #expect(session.error == nil)
        #expect(session.path == nil)
    }

    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device))
    func aMovieNoLongerWantedIsNotShown() throws {
        let renderer = try Self.canvas.makeRenderer()
        let movies = SWFMovieSource(fileSystem: InMemoryFileSource(), loadsImmediately: true)
        let session = MenuMovieSession(
            movies: movies, hud: HUDCoordinator(movies: movies), label: "test"
        ) { renderer }
        session.start(Self.movie, while: { false })
        #expect(session.error == nil)
        #expect(session.loadedRenderer == nil)
    }
}
