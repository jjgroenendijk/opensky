// The movie half of every vanilla menu: it takes the one SWF layer from the HUD,
// brings the movie up when it is decoded, and hands the layer back on stop. A
// failure becomes `error`, never a thrown error out of a control action.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyRendering

/// What one menu does to its movie during bring-up.
public struct MenuMovie {
    public var path: String
    /// Frames the movie's own fade needs to settle.
    public var activationTicks: Int
    public var adaptScene: (SWFMovieScene) -> SWFMovieScene
    public var prepare: ((SWFMovieRuntime) -> Void)?
    /// Throws to refuse a movie that came up wrong; the layer then goes back.
    public var activate: (SWFMovieRuntime) throws -> Void
    /// Runs after the activation ticks, for the first publish.
    public var didLoad: () -> Void

    public init(
        path: String,
        activationTicks: Int = 0,
        adaptScene: @escaping (SWFMovieScene) -> SWFMovieScene = { $0 },
        prepare: ((SWFMovieRuntime) -> Void)? = nil,
        activate: @escaping (SWFMovieRuntime) throws -> Void = { _ in },
        didLoad: @escaping () -> Void = {}
    ) {
        self.path = path
        self.activationTicks = activationTicks
        self.adaptScene = adaptScene
        self.prepare = prepare
        self.activate = activate
        self.didLoad = didLoad
    }
}

/// A movie the menu refused after bring-up, with the readout text.
public struct MenuMovieRefusal: Error, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

/// One menu's hold on the SWF layer. Each start cancels an older request, so a
/// movie decoded late opens only for the newest open.
public final class MenuMovieSession {
    public private(set) var isLoaded = false
    public private(set) var error: String?
    /// The movie requested last, loaded or not; nil after `stop()`.
    public private(set) var path: String?
    public private(set) var holdsLayer = false
    private var request = 0
    private let movies: SWFMovieSource?
    private let hud: HUDCoordinator?
    private let renderer: () -> Renderer?
    private let label: String
    private let logger: EngineLogger?

    public init(
        movies: SWFMovieSource?,
        hud: HUDCoordinator?,
        label: String,
        logger: EngineLogger? = nil,
        renderer: @escaping () -> Renderer?
    ) {
        self.movies = movies
        self.hud = hud
        self.label = label
        self.logger = logger
        self.renderer = renderer
    }

    /// The renderer while the movie is up, for sending it input.
    public var loadedRenderer: Renderer? {
        isLoaded ? renderer() : nil
    }

    public var runtime: SWFMovieRuntime? {
        loadedRenderer?.swfRuntime
    }

    public func start(_ movie: MenuMovie, while isWanted: @escaping () -> Bool = { true }) {
        guard let hud, let movies, renderer() != nil, movies.isAvailable else {
            isLoaded = false
            error = "No game data located."
            return
        }
        if !holdsLayer {
            hud.suspend()
            holdsLayer = true
        }
        path = movie.path
        isLoaded = false
        request += 1
        let current = request
        movies.request(movie.path, while: { [weak self] in
            self?.request == current
        }, then: { [weak self] result in
            guard isWanted() else { return }
            self?.show(result, movie: movie)
        })
    }

    /// Cancels a pending movie and gives the layer back to the HUD.
    public func stop() {
        request += 1
        path = nil
        isLoaded = false
        guard holdsLayer else { return }
        holdsLayer = false
        error = nil
        hud?.start()
    }

    /// Applies `body` to the live movie. Without a movie it does nothing.
    public func publish(_ body: (SWFMovieRuntime) -> Void) {
        guard let renderer = loadedRenderer else { return }
        do {
            try renderer.updateSWFRuntime(body)
        } catch {
            record(error)
        }
    }

    public func record(_ error: any Error) {
        self.error = String(describing: error)
        logger?.error("[ERROR] \(label): \(String(describing: error), privacy: .public)")
    }

    private func show(_ result: Result<SWFMovieScene, AssetLoadFailure>, movie: MenuMovie) {
        guard let renderer = renderer() else { return }
        do {
            let scene = try movie.adaptScene(result.get())
            guard try renderer.startMenuMovie(scene, prepare: movie.prepare) else {
                isLoaded = false
                error = "SWF runtime unavailable."
                return
            }
            var refusal: (any Error)?
            try renderer.updateSWFRuntime { runtime in
                do {
                    try movie.activate(runtime)
                } catch {
                    refusal = error
                }
            }
            if let refusal {
                stop()
                error = String(describing: refusal)
                return
            }
            for _ in 0 ..< movie.activationTicks {
                try renderer.advanceSWFRuntime()
            }
            isLoaded = true
            error = nil
            movie.didLoad()
        } catch {
            isLoaded = false
            record(error)
        }
    }
}
