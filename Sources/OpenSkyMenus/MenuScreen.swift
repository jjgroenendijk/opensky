// The shared shell of a small menu screen: it opens on the menu stack, brings up its
// movie, routes keys and the cursor, hands the movie's calls to the screen after each
// step, and draws a text panel while the movie is missing.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyRendering

/// What every menu screen needs from the app.
public protocol MenuScreenWorld: SWFLayerWorld {
    /// Receives keys while a screen is open.
    var menuInputConsumer: (any MenuInputConsumer)? { get }
    func showHUDNotification(_ text: String)
}

/// A screen subclass sets what its movie and readout show; the base runs the plumbing.
public class MenuScreen<Event> {
    public let identifier: MenuIdentifier
    public private(set) var isOpen = false
    /// What the last action did.
    public var lastResult = "none"
    /// The movie reads the arrow keys itself, as a slider or a list does.
    let movieReadsKeys: Bool
    let menuMode: MenuModeController
    private weak var screenWorld: (any MenuScreenWorld)?
    let movie: MenuMovieDriver<Event>

    init(
        identifier: MenuIdentifier,
        movieReadsKeys: Bool,
        menuMode: MenuModeController,
        layer: (movies: SWFMovieSource?, hud: HUDCoordinator?),
        world: (any MenuScreenWorld)?
    ) {
        self.identifier = identifier
        self.movieReadsKeys = movieReadsKeys
        self.menuMode = menuMode
        screenWorld = world
        movie = MenuMovieDriver(
            movies: layer.movies, hud: layer.hud, label: "\(identifier.name) movie"
        ) { [weak world] in world?.renderer }
    }

    /// Opens the screen with `path`; `activate` runs once the movie is up.
    func present(
        path: String,
        prepare: ((SWFMovieRuntime) -> Void)? = nil,
        activate: @escaping (SWFMovieRuntime) throws -> Void = { _ in }
    ) {
        isOpen = true
        menuMode.inputConsumer = screenWorld?.menuInputConsumer
        menuMode.present(identifier)
        movie.start(MenuMovie(
            path: path, prepare: prepare, activate: activate,
            didLoad: { [weak self] in self?.publish() }
        ), while: { [weak self] in self?.isOpen == true })
        publish()
    }

    public func close() {
        guard isOpen else { return }
        isOpen = false
        movie.stop()
        screenWorld?.uiScene = .empty
        menuMode.dismiss(identifier)
        didClose()
    }

    public func route(_ event: MenuInputEvent) {
        guard isOpen else { return }
        if movie.isLoaded, movieReadsKeys, event != .button(.cancel) {
            movie.route(event)
            return
        }
        handleKey(event)
        publish()
    }

    /// The cursor goes to the movie, whose buttons take the click.
    public func route(_ event: MenuPointerEvent) {
        guard isOpen else { return }
        if movie.isLoaded {
            movie.route(event)
        } else if event.phase == .pressed {
            route(.button(.accept))
        }
    }

    public func tick(now: Double) {
        for event in movie.tick(now: now) where isOpen {
            handle(event)
        }
    }

    func publish() {
        guard isOpen else { return }
        guard movie.isLoaded else {
            screenWorld?.uiScene = panel.scene
            return
        }
        screenWorld?.uiScene = .empty
        movie.publish(publishMovie)
    }

    func notify(_ text: String) {
        screenWorld?.showHUDNotification(text)
    }

    // MARK: - What a screen sets

    var panel: MenuTextPanel {
        MenuTextPanel(title: identifier.name, lines: [], hint: "Esc: close")
    }

    func handleKey(_ event: MenuInputEvent) {
        if event == .button(.cancel) {
            close()
        }
    }

    func handle(_: Event) {}

    func publishMovie(_: SWFMovieRuntime) {}

    func didClose() {}
}
