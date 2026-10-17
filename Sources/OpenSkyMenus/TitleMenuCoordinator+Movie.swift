// The vanilla main menu movie, its Load list included. A movie that does not load
// leaves the engine rows in charge and a readout, never a thrown error.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyRendering

extension TitleMenuCoordinator {
    static let movieLogger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Menus"
    )
    static let version = "OpenSky"

    func startMovie() {
        let hasSaves = entries.contains(.resume)
        movie.start(MenuMovie(
            path: TitleMenuMovieBridge.moviePath,
            activationTicks: TitleMenuMovieBridge.activationTicks,
            adaptScene: { scene in
                scene.addingImageSlot(
                    TitleMenuLoadBridge.screenshotSlot,
                    width: TitleMenuLoadBridge.screenshotWidth,
                    height: TitleMenuLoadBridge.screenshotHeight
                )
            },
            prepare: { [weak self] runtime in
                TitleMenuMovieBridge.prepare(runtime: runtime) { [weak self] request in
                    self?.pendingRequest = request
                }
                TitleMenuLoadBridge.prepare(runtime: runtime) { [weak self] call in
                    self?.pendingLoadCalls.append(call)
                }
            },
            activate: { runtime in
                TitleMenuMovieBridge.activate(
                    runtime: runtime, hasSaves: hasSaves, version: Self.version
                )
            },
            didLoad: { [weak self] in self?.world?.showTitleBackdrop(true) }
        ))
    }

    func stopMovie() {
        movie.stop()
        pendingRequest = nil
        pendingLoadCalls = []
        world?.showTitleBackdrop(false)
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
            movie.record(error)
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
