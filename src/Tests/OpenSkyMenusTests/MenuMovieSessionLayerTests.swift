// MenuMovieSession's layer hand-back without a Metal device.

@testable import OpenSkyMenus
import Testing

@MainActor
struct MenuMovieSessionLayerTests {
    /// A session that does not hold the layer leaves it where it is.
    @Test func aSessionWithoutTheLayerDoesNotReclaimIt() {
        let movies = SWFMovieSource()
        let session = MenuMovieSession(
            movies: movies, hud: HUDCoordinator(movies: movies), label: "test"
        ) { nil }
        session.reclaimLayer()
        #expect(!session.holdsLayer)
        #expect(session.path == nil)
    }
}
