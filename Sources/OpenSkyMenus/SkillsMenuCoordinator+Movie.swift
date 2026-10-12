// The skills menu's two vanilla movies on the one SWF layer. A movie that does not
// load leaves the engine rows in the sidebar in charge, never a thrown error.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyRendering

extension SkillsMenuCoordinator {
    /// The movie the page needs: the level-up buttons while a pick is owed.
    var wantedMoviePath: String? {
        guard let model, movieEnabled else { return nil }
        return model.page == .levelUp ? LevelUpMenuMovieBridge.moviePath : StatsMenuMovieBridge
            .moviePath
    }

    /// Loads the movie the page needs, or sends the model to the one already up.
    func syncMovie() {
        guard let wanted = wantedMoviePath else { return }
        guard wanted == moviePath else {
            startMovie(wanted)
            return
        }
        guard movieLoaded, let renderer = world?.renderer else { return }
        publish(renderer: renderer)
    }

    func startMovie(_ path: String) {
        guard let hud, world?.renderer != nil, movies?.isAvailable == true else {
            movieLoaded = false
            movieError = "No game data located."
            return
        }
        if !holdsLayer {
            hud.suspend()
            holdsLayer = true
        }
        moviePath = path
        movieLoaded = false
        movieRequest += 1
        let request = movieRequest
        movies?.request(path, while: { [weak self] in
            self?.movieRequest == request
        }, then: { [weak self] result in
            self?.showMovie(result, path: path)
        })
    }

    /// Runs when the movie is decoded, which may be a later frame than the open.
    func showMovie(_ result: Result<SWFMovieScene, AssetLoadFailure>, path: String) {
        guard let renderer = world?.renderer, model != nil else { return }
        do {
            let started = try renderer.startMenuMovie(result.get()) { [weak self] runtime in
                Self.prepare(runtime, path: path) { kind in
                    self?.pendingChoices.append(kind)
                }
            }
            guard started else {
                movieError = "SWF runtime unavailable."
                return
            }
            try renderer.updateSWFRuntime { runtime in
                if path == LevelUpMenuMovieBridge.moviePath {
                    LevelUpMenuMovieBridge.activate(runtime: runtime)
                } else {
                    StatsMenuMovieBridge.activate(runtime: runtime)
                }
            }
            movieLoaded = true
            movieError = nil
            publish(renderer: renderer)
        } catch {
            movieLoaded = false
            movieError = String(describing: error)
        }
    }

    func stopMovie() {
        movieRequest += 1
        moviePath = nil
        movieLoaded = false
        pendingChoices = []
        guard holdsLayer else { return }
        holdsLayer = false
        movieError = nil
        hud?.start()
    }

    func publish(renderer: Renderer) {
        guard let model else { return }
        do {
            try renderer.updateSWFRuntime { runtime in
                if model.page == .levelUp {
                    LevelUpMenuMovieBridge.highlight(model.selectedAttribute, runtime: runtime)
                } else {
                    StatsMenuMovieBridge.publish(model, runtime: runtime)
                }
            }
        } catch {
            movieError = String(describing: error)
        }
    }

    /// Steps the movie, then applies the buttons it pressed.
    public func tick(now: Double) {
        guard movieLoaded, let renderer = world?.renderer else {
            framePacer = MenuMovieFramePacer()
            return
        }
        let rate = Double(renderer.swfRuntime?.movie.frameRate ?? 0)
        do {
            for _ in 0 ..< framePacer.ticks(at: now, frameRate: rate) {
                try renderer.advanceSWFRuntime()
            }
        } catch {
            movieError = String(describing: error)
        }
        applyChoices()
    }

    /// A click on a level-up button makes the same pick as the accept key.
    func applyChoices() {
        guard !pendingChoices.isEmpty else { return }
        let choices = pendingChoices
        pendingChoices = []
        for kind in choices where model?.page == .levelUp {
            perform(.chooseAttribute(kind))
        }
        syncMovie()
    }

    private static func prepare(
        _ runtime: SWFMovieRuntime,
        path: String,
        onChoice: @escaping @MainActor @Sendable (ActorValueKind) -> Void
    ) {
        if path == LevelUpMenuMovieBridge.moviePath {
            LevelUpMenuMovieBridge.prepare(runtime: runtime, onChoice: onChoice)
        } else {
            StatsMenuMovieBridge.prepare(runtime: runtime)
        }
    }
}
