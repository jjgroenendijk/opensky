// The vanilla main menu movie, its Load list included. A movie that does not load
// leaves the engine rows in charge and a readout, never a thrown error.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyRendering

extension TitleMenuCoordinator {
    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Menus"
    )
    static let version = "OpenSky"

    func startMovie() {
        guard let hud, world?.renderer != nil, movies?.isAvailable == true else {
            movieLoaded = false
            movieError = "No game data located."
            return
        }
        hud.suspend()
        movieRequest += 1
        let request = movieRequest
        movies?.request(TitleMenuMovieBridge.moviePath, while: { [weak self] in
            self?.movieRequest == request
        }, then: { [weak self] result in
            self?.showMovie(result)
        })
    }

    /// Runs when the movie is decoded, which may be a later frame than the open.
    func showMovie(_ result: Result<SWFMovieScene, AssetLoadFailure>) {
        guard let renderer = world?.renderer else { return }
        do {
            try renderer.setSWFMovie(result.get().addingImageSlot(
                TitleMenuLoadBridge.screenshotSlot,
                width: TitleMenuLoadBridge.screenshotWidth,
                height: TitleMenuLoadBridge.screenshotHeight
            ))
            renderer.swfEnabled = true
            renderer.swfScale = 1
            let started = try renderer.startSWFRuntime { [weak self] runtime in
                TitleMenuMovieBridge.prepare(runtime: runtime) { [weak self] request in
                    self?.pendingRequest = request
                }
                TitleMenuLoadBridge.prepare(runtime: runtime) { [weak self] call in
                    self?.pendingLoadCalls.append(call)
                }
            }
            guard started != nil else {
                movieLoaded = false
                movieError = "SWF runtime unavailable."
                return
            }
            let hasSaves = entries.contains(.resume)
            try renderer.updateSWFRuntime { runtime in
                TitleMenuMovieBridge.activate(
                    runtime: runtime, hasSaves: hasSaves, version: Self.version
                )
            }
            for _ in 0 ..< TitleMenuMovieBridge.activationTicks {
                try renderer.advanceSWFRuntime()
            }
            world?.showTitleBackdrop(true)
            movieLoaded = true
            movieError = nil
        } catch {
            movieLoaded = false
            movieError = String(describing: error)
            Self.logger.error("[ERROR] title movie: \(String(describing: error), privacy: .public)")
        }
    }

    func stopMovie() {
        movieRequest += 1
        movieLoaded = false
        movieError = nil
        pendingRequest = nil
        pendingLoadCalls = []
        world?.showTitleBackdrop(false)
        hud?.start()
    }

    func routeMovie(_ event: MenuInputEvent, renderer: Renderer) {
        routeMovie(renderer: renderer) { TitleMenuMovieBridge.handle(event, runtime: $0) }
    }

    /// The movie hit tests the pointer itself. The engine rows have no layout to
    /// hit, so without the movie a pointer event does nothing.
    public func route(_ event: MenuPointerEvent) {
        guard isOpen, loadPage == nil, movieLoaded, let renderer = world?.renderer else { return }
        routeMovie(renderer: renderer) { TitleMenuMovieBridge.handle(event, runtime: $0) }
    }

    private func routeMovie(renderer: Renderer, _ inject: (SWFMovieRuntime) -> Void) {
        do {
            try renderer.updateSWFRuntime(inject)
        } catch {
            movieError = String(describing: error)
        }
        answerLoadCalls(renderer: renderer)
        guard let request = pendingRequest else { return }
        pendingRequest = nil
        apply(request)
    }

    /// The row the movie picked. Credits have no vanilla screen yet, so the movie
    /// goes back to its main rows. Load runs in the movie (`answerLoadCalls`).
    func apply(_ request: TitleMenuMovieBridge.Request) {
        switch request {
        case .resume: activate(.resume)
        case .new: activate(.new)
        case .quit: activate(.quit)
        case .credits:
            lastResult = "Credits: not shown"
            try? world?.renderer?.updateSWFRuntime(TitleMenuMovieBridge.returnToMain(runtime:))
        }
    }
}
