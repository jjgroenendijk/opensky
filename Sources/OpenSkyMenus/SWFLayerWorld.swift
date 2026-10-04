// The one SWF layer that the HUD, the menus, and the UI Lab take turns to own.

import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyRendering
import Synchronization

/// What a menu coordinator reads from the app. nil while Metal 4 is unavailable.
public protocol SWFLayerWorld: AnyObject {
    var renderer: Renderer? { get }
}

/// Menu movies, decoded off the main actor and kept for the session, so a menu that
/// opens again does not decode its movie again (docs/decisions/concurrency.md).
public final class SWFMovieSource {
    public typealias Use = (Result<SWFMovieScene, AssetLoadFailure>) -> Void

    /// Set by the app; nil without game data.
    public var fileSystem: (any GameFileSource)? {
        didSet {
            scenes = nil
            cachedPaths = nil
            waiting = []
        }
    }

    /// Loads on the caller, for tests and tools without a frame loop.
    public var loadsImmediately = false
    private var scenes: AssetLoader<String, SWFMovieScene>?
    private struct Waiting {
        let path: String
        let isWanted: () -> Bool
        let use: Use
    }

    private var waiting: [Waiting] = []
    private var cachedPaths: [String]?
    private var isListing = false

    public init(fileSystem: (any GameFileSource)? = nil, loadsImmediately: Bool = false) {
        self.fileSystem = fileSystem
        self.loadsImmediately = loadsImmediately
    }

    public var isAvailable: Bool {
        fileSystem != nil
    }

    /// The movies the HUD and the menus open, warmed at launch. The journal shares
    /// the system menu's movie.
    public static let menuMoviePaths = [
        HUDMovieBridge.moviePath, TitleMenuMovieBridge.moviePath, SystemMenuMovieBridge.moviePath,
        InventoryMenuMovieBridge.moviePath, ContainerMenuMovieBridge.containerMoviePath,
        ContainerMenuMovieBridge.barterMoviePath, DialogueMenuMovieBridge.moviePath
    ]

    /// Calls `use` now when the movie is decoded, else after the drain that brings it.
    /// `isWanted` is checked first then, so a menu closed meanwhile does not open.
    public func request(
        _ path: String,
        while isWanted: @escaping () -> Bool = { true },
        then use: @escaping Use
    ) {
        guard let scenes = loader() else {
            use(.failure(AssetLoadFailure(reason: "No game data located.")))
            return
        }
        var state = scenes.state(of: path)
        if case .loading = state, loadsImmediately {
            scenes.drain()
            state = scenes.state(of: path)
        }
        switch state {
        case let .ready(scene): use(.success(scene))
        case let .failed(failure): use(.failure(failure))
        case .loading: waiting.append(Waiting(path: path, isWanted: isWanted, use: use))
        }
    }

    /// Warms movies that menus open later, such as the HUD and the inventory.
    public func prefetch(_ paths: [String]) {
        guard let scenes = loader() else { return }
        for path in paths {
            scenes.prefetch(path)
        }
    }

    /// Takes decoded movies in and opens the menus that waited, oldest first.
    public func drain() {
        guard let scenes, !waiting.isEmpty || scenes.pendingCount > 0 else { return }
        scenes.drain()
        let pending = waiting
        waiting = []
        for entry in pending {
            switch scenes.state(of: entry.path) {
            case .loading: waiting.append(entry)
            case let .ready(scene) where entry.isWanted(): entry.use(.success(scene))
            case let .failed(failure) where entry.isWanted(): entry.use(.failure(failure))
            case .ready, .failed: break
            }
        }
    }

    /// Every `Interface\*.swf` movie. Listing walks every archive index, so it runs
    /// once, off the main actor; the list is empty until it is built.
    public var moviePaths: [String] {
        if let cachedPaths {
            return cachedPaths
        }
        guard let fileSystem else { return [] }
        if loadsImmediately {
            cachedPaths = SWFMovieLoader.moviePaths(in: fileSystem)
            return cachedPaths ?? []
        }
        if !isListing {
            isListing = true
            Task { [weak self] in
                let paths = await Self.listMovies(fileSystem)
                self?.cachedPaths = paths
            }
        }
        return []
    }

    @concurrent
    nonisolated private static func listMovies(_ files: any GameFileSource) async -> [String] {
        SWFMovieLoader.moviePaths(in: files)
    }

    private func loader() -> AssetLoader<String, SWFMovieScene>? {
        if let scenes {
            return scenes
        }
        guard let fileSystem else { return nil }
        let box = SWFMovieLoaderBox()
        let load: @Sendable (String) throws -> SWFMovieScene = { path in
            try box.loader.withLock { loader in
                let movies = loader ?? SWFMovieLoader(fileSystem: fileSystem)
                loader = movies
                return try movies.load(path: path)
            }
        }
        let worker: any AssetLoadWorking<String, SWFMovieScene> = loadsImmediately
            ? ImmediateAssetLoadWorker(load: load)
            : SerialAssetLoadWorker(load: load)
        let scenes = AssetLoader(worker: worker)
        self.scenes = scenes
        return scenes
    }
}

/// The worker's movie loader, with its import and font caches.
nonisolated private final class SWFMovieLoaderBox: Sendable {
    let loader = Mutex<SWFMovieLoader?>(nil)
}

extension Renderer {
    /// Shows a menu movie at full scale and starts its runtime. False when no runtime started.
    public func startMenuMovie(
        _ scene: SWFMovieScene, prepare: ((SWFMovieRuntime) -> Void)? = nil
    ) throws -> Bool {
        try setSWFMovie(scene)
        swfEnabled = true
        swfScale = 1
        return try startSWFRuntime(prepare: prepare) != nil
    }
}
