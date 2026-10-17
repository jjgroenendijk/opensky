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
    /// Writes the session as a Skyrim save under a new name; returns the file name.
    @discardableResult
    func exportSkyrimSave() async throws -> String
    /// The words the save pages and progress lines use.
    var saveTexts: SaveTexts { get }
}

extension SaveGameService {
    public var saveTexts: SaveTexts {
        .vanilla
    }

    public func exportSkyrimSave() async throws -> String {
        throw CocoaError(.featureUnsupported)
    }
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
    /// On by default, so play mode draws the menu. The HUD is suspended while
    /// the movie holds the one SWF layer.
    public private(set) var movieEnabled = true
    /// Calls the movie made during the last event or frame, answered after it.
    var pendingMovieCalls: [SystemMenuMovieBridge.Call] = []
    /// The movie's save list in its own order, without the New Save row.
    var movieSaveRows: [SaveSlotRow] = []
    var movieListSaving = false
    var framePacer = MenuMovieFramePacer()
    /// Called once; finding the data root walks the file system.
    public var locateDataRoot: () -> GameDataRoot? = { try? GameDataLocator.locate() }
    private var dataRoot: GameDataRoot?
    private var dataRootResolved = false

    private let menuMode: MenuModeController
    private let movies: SWFMovieSource
    private let hud: HUDCoordinator
    weak let world: SystemMenuWorld?

    public init(
        menuMode: MenuModeController,
        movies: SWFMovieSource,
        hud: HUDCoordinator,
        world: SystemMenuWorld? = nil
    ) {
        self.menuMode = menuMode
        self.movies = movies
        self.hud = hud
        self.world = world
    }

    lazy var movie = MenuMovieSession(
        movies: movies, hud: hud, label: "system menu movie", logger: Self.logger
    ) { [weak self] in self?.world?.renderer }

    public var movieLoaded: Bool {
        movie.isLoaded
    }

    public var movieError: String? {
        movie.error
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
        if let saves {
            Task { await saves.refreshSaveRows() }
        }
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
        movie.stop()
    }

    public func setMovieEnabled(_ enabled: Bool) {
        guard enabled != movieEnabled else { return }
        movieEnabled = enabled
        guard model.isOpen else { return }
        if enabled {
            startMovie()
        } else {
            movie.stop()
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
        if sendsToMovie(event) {
            sendToMovie(event)
            return
        }
        guard model.page == .main else {
            routePage(event)
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
        movie.start(MenuMovie(
            path: SystemMenuMovieBridge.moviePath,
            activationTicks: SystemMenuMovieBridge.activationTicks,
            prepare: SystemMenuMovieBridge.prepare(runtime:),
            activate: { [weak self] runtime in
                SystemMenuMovieBridge.activate(runtime: runtime) { [weak self] in
                    self?.close()
                }
                SettingsMovieBridge.register(runtime: runtime) { [weak self] group in
                    self?.openSettingsCategory(group)
                }
                SystemMenuMovieBridge.registerCalls(runtime: runtime) { [weak self] call in
                    self?.pendingMovieCalls.append(call)
                }
            }
        ))
    }

    public var snapshot: SystemMenuControlSnapshot {
        let runtime = movie.runtime
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

extension SystemMenuCoordinator: SystemMenuControlProviding {
    public var systemMenuIsOpen: Bool {
        isOpen
    }

    public var systemMenuMovieEnabled: Bool {
        get { movieEnabled }
        set { setMovieEnabled(newValue) }
    }

    public var systemMenuMasterVolume: Float {
        get { masterVolume }
        set { masterVolume = newValue }
    }

    public func openSystemMenu() {
        open()
    }

    public func closeSystemMenu() {
        close()
    }

    public func sendSystemMenuInput(_ event: MenuInputEvent) {
        route(event)
    }

    public func deleteSelectedSave() {
        requestDeleteSelectedSave()
    }

    public var systemMenuSnapshot: SystemMenuControlSnapshot {
        snapshot
    }
}
