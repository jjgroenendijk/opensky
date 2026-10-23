// The skills menu's two vanilla movies on the one SWF layer. A movie that does not
// load leaves the engine rows in charge, never a thrown error.

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
        guard wanted == movie.path else {
            startMovie(wanted)
            return
        }
        guard movieLoaded, let renderer = world?.renderer else { return }
        publish(renderer: renderer)
    }

    func startMovie(_ path: String) {
        let isLevelUp = path == LevelUpMenuMovieBridge.moviePath
        movie.start(MenuMovie(
            path: path,
            prepare: { [weak self] runtime in
                Self.prepare(runtime, path: path, onCamera: { alpha in
                    self?.sky.movieAlpha = alpha
                }, onChoice: { kind in
                    self?.pendingChoices.append(kind)
                })
            },
            activate: { runtime in
                if isLevelUp {
                    LevelUpMenuMovieBridge.activate(runtime: runtime)
                } else {
                    StatsMenuMovieBridge.activate(runtime: runtime)
                }
            },
            didLoad: { [weak self] in
                guard let self, let renderer = world?.renderer else { return }
                publish(renderer: renderer)
            }
        ), while: { [weak self] in self?.model != nil })
    }

    func stopMovie() {
        movie.stop()
        pendingChoices = []
    }

    func publish(renderer: Renderer) {
        guard let model else { return }
        do {
            try renderer.updateSWFRuntime { runtime in
                if model.page == .levelUp {
                    LevelUpMenuMovieBridge.highlight(model.selectedAttribute, runtime: runtime)
                } else {
                    StatsMenuMovieBridge.publish(
                        model, namePoints: sky.namePoints, runtime: runtime
                    )
                }
            }
        } catch {
            movie.record(error)
        }
    }

    /// Steps the movie, then applies the buttons it pressed.
    public func tick(now: Double) {
        tickSky(now: now)
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
            movie.record(error)
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
        onCamera: @escaping @MainActor @Sendable (Float) -> Void,
        onChoice: @escaping @MainActor @Sendable (ActorValueKind) -> Void
    ) {
        if path == LevelUpMenuMovieBridge.moviePath {
            LevelUpMenuMovieBridge.prepare(runtime: runtime, onChoice: onChoice)
        } else {
            StatsMenuMovieBridge.prepare(runtime: runtime, onCamera: onCamera)
        }
    }
}
