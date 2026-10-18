// One menu's movie: its hold on the SWF layer, its frame steps, and the calls it
// makes to the engine. A call runs after the movie step that made it, so engine
// code never changes the movie while the movie is running.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyRendering

public final class MenuMovieDriver<Event> {
    public let session: MenuMovieSession
    private var pacer = MenuMovieFramePacer()
    private var pending: [Event] = []
    private let renderer: () -> Renderer?

    public init(
        movies: SWFMovieSource?,
        hud: HUDCoordinator?,
        label: String,
        renderer: @escaping () -> Renderer?
    ) {
        self.renderer = renderer
        session = MenuMovieSession(movies: movies, hud: hud, label: label, renderer: renderer)
    }

    public var isLoaded: Bool {
        session.isLoaded
    }

    public var error: String? {
        session.error
    }

    public func start(_ movie: MenuMovie, while isWanted: @escaping () -> Bool = { true }) {
        pending = []
        pacer = MenuMovieFramePacer()
        session.start(movie, while: isWanted)
    }

    public func stop() {
        pending = []
        session.stop()
    }

    /// Records a movie call; `tick` hands it to the menu.
    public func post(_ event: Event) {
        pending.append(event)
    }

    public func publish(_ body: (SWFMovieRuntime) -> Void) {
        session.publish(body)
    }

    /// Sends a key to the movie, for a menu whose movie reads keys itself.
    public func route(_ event: MenuInputEvent) {
        session.publish { _ = TitleMenuMovieBridge.handle(event, runtime: $0) }
    }

    /// Sends the cursor to the movie, so its buttons and lists take clicks.
    public func route(_ event: MenuPointerEvent) {
        session.publish { _ = TitleMenuMovieBridge.handle(event, runtime: $0) }
    }

    /// Steps the movie at its frame rate, then returns the calls it made.
    public func tick(now: Double) -> [Event] {
        guard session.isLoaded, let renderer = renderer() else {
            pacer = MenuMovieFramePacer()
            return takeEvents()
        }
        let rate = Double(renderer.swfRuntime?.movie.frameRate ?? 0)
        do {
            for _ in 0 ..< pacer.ticks(at: now, frameRate: rate) {
                try renderer.advanceSWFRuntime()
            }
        } catch {
            session.record(error)
        }
        return takeEvents()
    }

    private func takeEvents() -> [Event] {
        let events = pending
        pending = []
        return events
    }
}
