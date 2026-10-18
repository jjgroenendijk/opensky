// The Creation Club store screen, offline: OpenSky does not reach Bethesda.net, so it
// shows the empty store and closes. See docs/engine/creation-club.md.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyRendering

public final class CreationClubMenuCoordinator: MenuScreen<CreationClubMovieEvent> {
    public static let identifier: MenuIdentifier = "Creation Club Menu"

    public init(
        menuMode: MenuModeController,
        movies: SWFMovieSource? = nil,
        hud: HUDCoordinator? = nil,
        world: (any MenuScreenWorld)? = nil
    ) {
        super.init(
            identifier: Self.identifier, movieReadsKeys: false, menuMode: menuMode,
            layer: (movies, hud), world: world
        )
    }

    @discardableResult
    public func open() -> Bool {
        guard !isOpen else { return false }
        lastResult = "Opened offline"
        present(path: CreationClubMenuMovieBridge.moviePath) { [weak self] runtime in
            CreationClubMenuMovieBridge.activate(runtime: runtime) { self?.movie.post($0) }
        }
        return true
    }

    override func handleKey(_ event: MenuInputEvent) {
        guard event == .button(.cancel) else { return }
        if movie.isLoaded {
            movie.publish(CreationClubMenuMovieBridge.release(runtime:))
        }
        close()
    }

    override func handle(_ event: CreationClubMovieEvent) {
        switch event {
        case .close: handleKey(.button(.cancel))
        }
    }

    override var panel: MenuTextPanel {
        MenuTextPanel(
            title: "Creation Club", lines: ["Offline: OpenSky does not connect to the store."],
            hint: "Esc: close"
        )
    }
}
