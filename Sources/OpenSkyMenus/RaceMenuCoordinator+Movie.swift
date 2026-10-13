// The vanilla race menu movie. A movie that does not load leaves the engine rows
// in charge and a readout, never a thrown error.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyRendering

extension RaceMenuCoordinator {
    func startMovie() {
        guard let hud, world?.renderer != nil, movies?.isAvailable == true else {
            movieLoaded = false
            movieError = "No game data located."
            return
        }
        hud.suspend()
        holdsLayer = true
        movieRequest += 1
        let request = movieRequest
        movies?.request(RaceMenuMovieBridge.moviePath, while: { [weak self] in
            self?.movieRequest == request
        }, then: { [weak self] result in
            self?.showMovie(result)
        })
    }

    /// Runs when the movie is decoded, which may be a later frame than the open.
    func showMovie(_ result: Result<SWFMovieScene, AssetLoadFailure>) {
        guard let renderer = world?.renderer, let model else { return }
        do {
            try renderer.setSWFMovie(result.get())
            renderer.swfEnabled = true
            renderer.swfScale = 1
            let started = try renderer.startSWFRuntime { [weak self] runtime in
                RaceMenuMovieBridge.prepare(runtime: runtime) { [weak self] request in
                    self?.pendingMovieRequests.append(request)
                }
            }
            guard let started else {
                movieLoaded = false
                movieError = "SWF runtime unavailable."
                return
            }
            guard RaceMenuMovieBridge.listsBuilt(runtime: started) else {
                stopMovie()
                movieError = "The movie's lists did not build; the engine rows are in charge."
                return
            }
            try renderer.updateSWFRuntime {
                RaceMenuMovieBridge.setPlatform(runtime: $0)
                RaceMenuMovieBridge.publish(model, runtime: $0)
            }
            movieLoaded = true
            movieError = nil
        } catch {
            movieLoaded = false
            movieError = String(describing: error)
        }
    }

    func stopMovie() {
        movieRequest += 1
        pendingMovieRequests = []
        movieLoaded = false
        guard holdsLayer else { return }
        holdsLayer = false
        movieError = nil
        hud?.start()
    }

    func routeMovie(_ event: MenuInputEvent, renderer: Renderer) {
        do {
            try renderer.updateSWFRuntime { RaceMenuMovieBridge.handle(event, runtime: $0) }
        } catch {
            movieError = String(describing: error)
        }
        applyMovieRequests(renderer: renderer)
    }

    /// The cursor drives the movie's lists and sliders, as in the game.
    public func route(_ event: MenuPointerEvent) {
        guard movieLoaded, let renderer = world?.renderer else {
            if event.phase == .pressed {
                route(.button(.accept))
            }
            return
        }
        do {
            try renderer.updateSWFRuntime { TitleMenuMovieBridge.handle(event, runtime: $0) }
        } catch {
            movieError = String(describing: error)
        }
        applyMovieRequests(renderer: renderer)
    }

    /// Steps the movie, then applies what it asked for in those frames.
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
        applyMovieRequests(renderer: renderer)
    }

    /// The movie's slider, race, and name changes reach the head at once. A race or
    /// sex change brings new options, and a new preset or mask moves other sliders, so
    /// those send the sliders again.
    func applyMovieRequests(renderer: Renderer?) {
        guard var model, !pendingMovieRequests.isEmpty else { return }
        let requests = pendingMovieRequests
        pendingMovieRequests = []
        let rows = model.rows
        var done = false
        var republish = false
        for request in requests {
            let before = (model.identity.race, model.identity.isFemale)
            switch request {
            case let .race(index): model.selectRace(at: index)
            case let .slider(id, value):
                guard rows.indices.contains(id) else { continue }
                model.set(rows[id], to: Float(value))
                republish = republish || Self.movesOtherSliders(rows[id])
            case let .name(name): model.setName(name)
            case let .zoom(zoomIn): isZoomedIn = zoomIn
            case .done: done = true
            }
            republish = refreshOptions(&model, before: before) || republish
        }
        if model.identity != self.model?.identity {
            world?.applyPlayerIdentity(model.identity)
        }
        self.model = model
        if republish {
            try? renderer?.updateSWFRuntime { RaceMenuMovieBridge.publish(model, runtime: $0) }
        }
        if done {
            close()
        }
    }

    static func movesOtherSliders(_ row: RaceMenuRow) -> Bool {
        switch row {
        case .headPreset, .tintMask, .sex: true
        default: false
        }
    }

    /// After a race or sex change the menu offers that race's choices. True when
    /// the options changed.
    func refreshOptions(_ model: inout RaceMenuModel, before: (FormID, Bool)) -> Bool {
        guard (model.identity.race, model.identity.isFemale) != before else { return false }
        let options = world?.raceMenuOptions(
            race: model.identity.race, isFemale: model.identity.isFemale
        )
        model.setOptions(options ?? .empty)
        return true
    }
}
