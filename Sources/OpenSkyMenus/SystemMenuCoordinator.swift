// The system menu: opening it pushes the engine's menu stack, which pauses the
// world sim and routes keys here. The vanilla movie is an optional
// presentation over `SystemMenuModel`. See docs/engine/system-menu.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyRendering

/// What the system menu reads from the app. The world is also the one menu
/// input consumer, which routes by the top of the menu stack.
public protocol SystemMenuWorld: SWFLayerWorld, MenuInputConsumer {
    var audioEnabled: Bool { get }
    func quitApplication()
    /// Ends the session and shows the title menu.
    func quitToMainMenu()
}

/// Saving and loading for the Save and Load pages and the quick keys. The file work
/// runs off the main actor; game state is read and applied on it.
public protocol SaveGameService: AnyObject {
    /// The newest listing read, empty before the first.
    var saveRows: [SaveSlotRow] { get }
    @discardableResult
    func refreshSaveRows() async -> [SaveSlotRow]
    /// Writes `slot`, or a new slot when nil; returns the slot written.
    @discardableResult
    func saveGame(slot: String?) async throws -> String
    func loadGame(slot: String) async throws
    func deleteSave(slot: String) async throws
}

public final class SystemMenuCoordinator {
    public static let identifier: MenuIdentifier = "SystemMenu"

    public internal(set) var model = SystemMenuModel()
    public internal(set) var settingsPage = SettingsPageModel(catalog: .vanilla)
    public internal(set) var saveLoadPage: SaveLoadPageModel?
    public internal(set) var controlsPage = ControlsPageModel()
    public internal(set) var quitPage: ConfirmationModel?
    /// The result of the last save, load, or remap, for the readout.
    public internal(set) var lastMessage: String?
    /// The running save, load, or delete; one at a time.
    public internal(set) var saveWork: Task<Void, Never>?
    public private(set) var settings: PlayerSettingsCoordinator?
    public weak var saves: SaveGameService?
    /// Off by default: the vanilla movie takes the one SWF layer from the HUD.
    public private(set) var movieEnabled = false
    public private(set) var movieLoaded = false
    /// Bumped by each open and close, so a movie decoded late opens only the newest.
    private var movieRequest = 0
    public private(set) var movieError: String?
    /// Called once; finding the data root walks the file system.
    public var locateDataRoot: () -> GameDataRoot? = { try? GameDataLocator.locate() }
    private var dataRoot: GameDataRoot?
    private var dataRootResolved = false

    private let menuMode: MenuModeController
    private let movies: SWFMovieSource
    private let hud: HUDCoordinator
    weak var world: SystemMenuWorld?

    public init(menuMode: MenuModeController, movies: SWFMovieSource, hud: HUDCoordinator) {
        self.menuMode = menuMode
        self.movies = movies
        self.hud = hud
    }

    public func attach(world: SystemMenuWorld) {
        self.world = world
    }

    public func attach(settings: PlayerSettingsCoordinator) {
        self.settings = settings
        settingsPage = SettingsPageModel(catalog: settings.store.catalog)
    }

    var renderer: Renderer? {
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
        dismiss()
    }

    /// Resume and cancel close the model first, so this skips the model guard.
    private func dismiss() {
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

    /// The settings store owns the value; this reads and writes through it.
    public var masterVolume: Float {
        get { Float(settings?.store.value(.masterVolume) ?? 1) }
        set { settings?.store.set(.masterVolume, to: Double(newValue)) }
    }

    /// On the main page the movie moves its own highlight, and accept opens the
    /// engine row the movie shows. A sub-page has its own model.
    public func route(_ event: MenuInputEvent) {
        guard model.isOpen else { return }
        guard model.page == .main else {
            routePage(event)
            return
        }
        if movieLoaded, let renderer, case .move = event {
            do {
                try SystemMenuMovieBridge.send(event, renderer: renderer)
            } catch {
                movieError = String(describing: error)
                Self.logger.error(
                    "[ERROR] system menu input: \(String(describing: error), privacy: .public)"
                )
            }
            return
        }
        if
            movieLoaded, event == .button(.accept),
            let entry = renderer?.swfRuntime.flatMap(SystemMenuMovieBridge.selectedEntry(runtime:))
        {
            model.select(entry)
        }
        if let outcome = model.handle(event) {
            apply(outcome)
        }
    }

    /// A sub-page is state on the model, not a second menu on the stack.
    func apply(_ outcome: SystemMenuOutcome) {
        switch outcome {
        case .resume:
            dismiss()
        case .quicksave:
            quicksave()
        case let .showPage(page):
            showPage(page)
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
        guard renderer != nil, movies.isAvailable else {
            movieLoaded = false
            movieError = "No game data located."
            return
        }
        hud.suspend()
        movieRequest += 1
        let request = movieRequest
        movies.request(SystemMenuMovieBridge.moviePath, while: { [weak self] in
            self?.movieRequest == request
        }, then: { [weak self] result in
            self?.showMovie(result)
        })
    }

    /// Runs when the movie is decoded, which may be a later frame than the open.
    private func showMovie(_ result: Result<SWFMovieScene, AssetLoadFailure>) {
        guard let renderer else { return }
        do {
            let scene = try result.get()
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
                SettingsMovieBridge.register(runtime: runtime) { [weak self] group in
                    self?.openSettingsCategory(group)
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
        movieRequest += 1
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
            movieState: runtime.flatMap(SystemMenuMovieBridge.currentState(runtime:)),
            page: pageSnapshot
        )
    }

    private static let logger = EngineLogger(
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

    public func deleteSelectedSave() {
        systemMenu.requestDeleteSelectedSave()
    }

    public var systemMenuSnapshot: SystemMenuControlSnapshot {
        systemMenu.snapshot
    }
}
