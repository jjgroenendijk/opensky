// A menu's second movie, drawn over its main one on the renderer's overlay layer.
// Each start cancels an older request, so a movie decoded late shows only for the
// newest open.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyRendering

public final class MenuMovieOverlay {
    public private(set) var isLoaded = false
    public private(set) var error: String?
    private var request = 0
    private let movies: SWFMovieSource?
    private let renderer: () -> Renderer?

    public init(movies: SWFMovieSource?, renderer: @escaping () -> Renderer?) {
        self.movies = movies
        self.renderer = renderer
    }

    /// `activate` runs once the movie is up; `prepare` runs before it starts.
    public func start(
        path: String,
        prepare: ((SWFMovieRuntime) -> Void)? = nil,
        activate: @escaping (SWFMovieRuntime) -> Void
    ) {
        stop()
        guard let movies, movies.isAvailable else { return }
        let current = request
        movies.request(path, while: { [weak self] in
            self?.request == current
        }, then: { [weak self] result in
            self?.show(result, prepare: prepare, activate: activate)
        })
    }

    public func stop() {
        request += 1
        guard isLoaded else { return }
        isLoaded = false
        record { try $0.setSWFOverlay(nil) }
    }

    public func publish(_ body: (SWFMovieRuntime) -> Void) {
        guard isLoaded else { return }
        record { try $0.updateSWFOverlay(body) }
    }

    public func tick() {
        guard isLoaded else { return }
        record { try $0.advanceSWFOverlay() }
    }

    private func show(
        _ result: Result<SWFMovieScene, AssetLoadFailure>,
        prepare: ((SWFMovieRuntime) -> Void)?,
        activate: @escaping (SWFMovieRuntime) -> Void
    ) {
        record { renderer in
            guard try renderer.setSWFOverlay(result.get(), prepare: prepare) != nil else { return }
            isLoaded = true
            error = nil
            try renderer.updateSWFOverlay(activate)
        }
    }

    private func record(_ body: (Renderer) throws -> Void) {
        guard let renderer = renderer() else { return }
        do {
            try body(renderer)
        } catch {
            self.error = String(describing: error)
        }
    }
}
