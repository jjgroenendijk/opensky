// The skills menu's two vanilla movies. The stats movie stays up the whole time; while
// a pick is owed it shows its level-up state and the level-up movie is drawn over it.
// A movie that does not load leaves the engine rows in charge, never a thrown error.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyRendering

extension SkillsMenuCoordinator {
    /// The stats movie, or nil when the movies are off.
    var wantedMoviePath: String? {
        model != nil && movieEnabled ? StatsMenuMovieBridge.moviePath : nil
    }

    /// Loads the stats movie, or sends the model to the one already up.
    func syncMovie() {
        syncLevelUpMovie()
        guard let wanted = wantedMoviePath else { return }
        guard wanted == movie.path else {
            startMovie(wanted)
            return
        }
        guard movieLoaded, let renderer = world?.renderer else { return }
        publish(renderer: renderer)
    }

    func startMovie(_ path: String) {
        movie.start(MenuMovie(
            path: path,
            prepare: { [weak self] runtime in
                StatsMenuMovieBridge.prepare(runtime: runtime) { alpha in
                    self?.sky.movieAlpha = alpha
                }
            },
            activate: { runtime in StatsMenuMovieBridge.activate(runtime: runtime) },
            didLoad: { [weak self] in
                guard let self, let renderer = world?.renderer else { return }
                publish(renderer: renderer)
            }
        ), while: { [weak self] in self?.model != nil })
    }

    /// Starts the level-up movie while a pick is owed and stops it after the last one.
    func syncLevelUpMovie() {
        let wanted = movieEnabled && model?.page == .levelUp
        guard wanted != levelUpShown else { return }
        levelUpShown = wanted
        guard wanted else {
            levelUpMovie.stop()
            return
        }
        levelUpMovie.start(
            path: LevelUpMenuMovieBridge.moviePath,
            prepare: { [weak self] runtime in
                LevelUpMenuMovieBridge.prepare(runtime: runtime) { kind in
                    self?.pendingChoices.append(kind)
                }
            },
            activate: { [weak self] runtime in
                LevelUpMenuMovieBridge.activate(runtime: runtime)
                if let kind = self?.model?.selectedAttribute {
                    LevelUpMenuMovieBridge.highlight(kind, runtime: runtime)
                }
            }
        )
    }

    func stopMovie() {
        movie.stop()
        levelUpMovie.stop()
        levelUpShown = false
        pendingChoices = []
    }

    func publish(renderer: Renderer) {
        guard let model else { return }
        do {
            try renderer.updateSWFRuntime { runtime in
                StatsMenuMovieBridge.publish(model, namePoints: sky.namePoints, runtime: runtime)
            }
            if model.page == .levelUp {
                try renderer.updateSWFOverlay { runtime in
                    LevelUpMenuMovieBridge.highlight(model.selectedAttribute, runtime: runtime)
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
                levelUpMovie.tick()
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
}
