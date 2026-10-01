// The system menu: opening it pushes the engine's menu stack, which pauses the
// world sim and routes keys here. The vanilla movie is an optional
// presentation over `SystemMenuModel`. See docs/engine/system-menu.md.

import OpenSkyGameData
import OpenSkyRendering
import OSLog

/// What the system menu reads from the app. The world is also the one menu
/// input consumer, which routes by the top of the menu stack.
public protocol SystemMenuWorld: SWFLayerWorld, MenuInputConsumer {
    var audioEnabled: Bool { get }
    var audioMasterVolume: Float { get set }
    func quitApplication()
}

public final class SystemMenuCoordinator {
    public static let identifier: MenuIdentifier = "SystemMenu"

    public private(set) var model = SystemMenuModel()
    /// Off by default: the vanilla movie takes the one SWF layer from the HUD.
    public private(set) var movieEnabled = false
    public private(set) var movieLoaded = false
    public private(set) var movieError: String?
    /// Called once; finding the data root walks the file system.
    public var locateDataRoot: () -> GameDataRoot? = { try? GameDataLocator.locate() }
    private var dataRoot: GameDataRoot?
    private var dataRootResolved = false

    private let menuMode: MenuModeController
    private let movies: SWFMovieSource
    private let hud: HUDCoordinator
    private weak var world: SystemMenuWorld?

    public init(menuMode: MenuModeController, movies: SWFMovieSource, hud: HUDCoordinator) {
        self.menuMode = menuMode
        self.movies = movies
        self.hud = hud
    }

    public func attach(world: SystemMenuWorld) {
        self.world = world
    }

    private var renderer: Renderer? {
        world?.renderer
    }

    public var isOpen: Bool {
        model.isOpen
    }

    public func open() {
        guard !model.isOpen else { return }
        model.open()
        menuMode.inputConsumer = world
        menuMode.present(Self.identifier)
        if movieEnabled {
            startMovie()
        }
    }

    public func close() {
        guard model.isOpen else { return }
        model.close()
        menuMode.dismiss(Self.identifier)
        if movieLoaded {
            stopMovie()
        }
    }

    public func setMovieEnabled(_ enabled: Bool) {
        guard enabled != movieEnabled else { return }
        movieEnabled = enabled
        guard model.isOpen else { return }
        if enabled {
            startMovie()
        } else {
            stopMovie()
        }
    }

    public var masterVolume: Float {
        get { world?.audioMasterVolume ?? 1 }
        set { world?.audioMasterVolume = newValue }
    }

    /// The movie gets the event first; the model handles what it leaves.
    public func route(_ event: MenuInputEvent) {
        guard model.isOpen else { return }
        if movieLoaded, let renderer {
            do {
                if try SystemMenuMovieBridge.send(event, renderer: renderer) {
                    return
                }
            } catch {
                movieError = String(describing: error)
                Self.logger.error(
                    "[ERROR] system menu input: \(String(describing: error), privacy: .public)"
                )
                return
            }
        }
        if let outcome = model.handle(event) {
            apply(outcome)
        }
    }

    /// Settings is state on the model, not a second menu on the stack.
    private func apply(_ outcome: SystemMenuOutcome) {
        switch outcome {
        case .resume:
            close()
        case .showSettings:
            break
        case .quit:
            close()
            world?.quitApplication()
        }
    }

    public var dataRootValue: GameDataRoot? {
        if !dataRootResolved {
            dataRoot = locateDataRoot()
            dataRootResolved = true
        }
        return dataRoot
    }

    public static func dataRootSourceLabel(_ source: GameDataRoot.Source) -> String {
        switch source {
        case .environment: "\(GameDataLocator.environmentKey) environment variable"
        case .userDefaults: "Settings"
        case .steamDefault: "Steam default"
        }
    }

    // MARK: - Movie

    /// A missing install or a movie the AS2 subset cannot run degrades to a
    /// readout, never to a thrown error out of a control action.
    private func startMovie() {
        guard let renderer, let loader = movies.loader else {
            movieLoaded = false
            movieError = "No game data located."
            return
        }
        do {
            hud.suspend()
            let scene = try loader.load(path: SystemMenuMovieBridge.moviePath)
            try renderer.setSWFMovie(scene)
            renderer.swfEnabled = true
            renderer.swfScale = 1
            let started = try renderer.startSWFRuntime(
                prepare: SystemMenuMovieBridge.prepare(runtime:)
            )
            guard started != nil else {
                movieLoaded = false
                movieError = "SWF runtime unavailable."
                return
            }
            try renderer.updateSWFRuntime { runtime in
                SystemMenuMovieBridge.activate(runtime: runtime) { [weak self] in
                    self?.close()
                }
            }
            for _ in 0 ..< SystemMenuMovieBridge.activationTicks {
                try renderer.advanceSWFRuntime()
            }
            movieLoaded = true
            movieError = nil
        } catch {
            movieLoaded = false
            movieError = String(describing: error)
            Self.logger.error(
                "[ERROR] system menu movie: \(String(describing: error), privacy: .public)"
            )
        }
    }

    /// Hands the SWF layer back to the HUD.
    private func stopMovie() {
        movieLoaded = false
        movieError = nil
        hud.start()
    }

    public var snapshot: SystemMenuControlSnapshot {
        let runtime = movieLoaded ? renderer?.swfRuntime : nil
        let diagnostics = renderer?.swfRuntime.map(SystemMenuMovieBridge.diagnostics(runtime:))
        return SystemMenuControlSnapshot(
            isOpen: model.isOpen,
            entryTitles: model.entries.map(\.title),
            selectedIndex: model.selectedIndex,
            lastOutcome: model.lastOutcome?.label,
            settingsRevealed: model.settingsRevealed,
            openMenus: menuMode.stack.identifiers.map(\.name),
            worldSimPaused: menuMode.isWorldSimPaused,
            dataRootPath: dataRootValue?.installURL.path(percentEncoded: false),
            dataRootSource: dataRootValue.map { Self.dataRootSourceLabel($0.source) },
            audioEnabled: world?.audioEnabled ?? false,
            movieEnabled: movieEnabled,
            movieLoaded: movieLoaded,
            movieError: movieError,
            movieDrawStats: movieLoaded
                ? (renderer?.lastSWFDrawStats ?? SWFDrawStats())
                : SWFDrawStats(),
            movieFaults: diagnostics?.faults ?? 0,
            movieMissingNames: diagnostics?.missingNames ?? 0,
            movieEntryTitles: runtime.map(SystemMenuMovieBridge.entryLabels(runtime:)) ?? [],
            movieState: runtime.flatMap(SystemMenuMovieBridge.currentState(runtime:))
        )
    }

    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "SystemMenu"
    )
}

/// Lets the app's provider object stand in for its `SystemMenuCoordinator`.
public protocol SystemMenuControlForwarding: SystemMenuControlProviding {
    var systemMenu: SystemMenuCoordinator { get }
}

extension SystemMenuControlForwarding {
    public var systemMenuIsOpen: Bool {
        systemMenu.isOpen
    }

    public var systemMenuMovieEnabled: Bool {
        get { systemMenu.movieEnabled }
        set { systemMenu.setMovieEnabled(newValue) }
    }

    public var systemMenuMasterVolume: Float {
        get { systemMenu.masterVolume }
        set { systemMenu.masterVolume = newValue }
    }

    public func openSystemMenu() {
        systemMenu.open()
    }

    public func closeSystemMenu() {
        systemMenu.close()
    }

    public func sendSystemMenuInput(_ event: MenuInputEvent) {
        systemMenu.route(event)
    }

    public var systemMenuSnapshot: SystemMenuControlSnapshot {
        systemMenu.snapshot
    }
}
