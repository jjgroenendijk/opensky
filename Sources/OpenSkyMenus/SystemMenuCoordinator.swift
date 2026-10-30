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
    /// `SetInChargen` turned saving off.
    var isSavingDisabled: Bool { get }
    /// Loads `slot` even though the load order changed since it was written, after the
    /// player answered `sSaveGameContentIsMissing`.
    func loadGame(slot: String, acceptingChangedContent: Bool) async throws
}

extension SaveGameService {
    public var saveTexts: SaveTexts {
        .vanilla
    }

    public var isSavingDisabled: Bool {
        false
    }

    public func loadGame(slot: String, acceptingChangedContent _: Bool) async throws {
        try await loadGame(slot: slot)
    }

    public func exportSkyrimSave() async throws -> String {
        throw CocoaError(.featureUnsupported)
    }
}

public final class SystemMenuCoordinator {
    public static let identifier: MenuIdentifier = "SystemMenu"

    public internal(set) var model = SystemMenuModel()
    public internal(set) var settingsPage: SettingsPageModel
    public internal(set) var saveLoadPage: SaveLoadPageModel?
    public internal(set) var controlsPage = ControlsPageModel()
    public internal(set) var quitPage: ConfirmationModel?
    /// The Help or Installed Content page while one is up.
    public internal(set) var topicPage: SystemMenuTopicPageModel?
    /// Set by the app; nil leaves both topic pages empty.
    public weak var topicSource: (any SystemMenuTopicSource)?
    /// The result of the last save, load, or remap, for the readout.
    public internal(set) var lastMessage: String?
    /// The running save, load, or delete; one at a time.
    public internal(set) var saveWork: Task<Void, Never>?
    public let settings: PlayerSettingsCoordinator
    public weak let saves: SaveGameService?
    /// On by default, so play mode draws the menu. The HUD is suspended while
    /// the movie holds the one SWF layer.
    public private(set) var movieEnabled = true
    /// Calls the movie made during the last event or frame, answered after it.
    var pendingMovieCalls: [SystemMenuMovieBridge.Call] = []
    /// The movie's save list in its own order, without the New Save row.
    var movieSaveRows: [SaveSlotRow] = []
    var movieListSaving = false
    var framePacer = MenuMovieFramePacer()
    /// The movie's `SystemPage` state at the last check, to see a topic's text close.
    var lastMovieState: Int?
    /// Called once; finding the data root walks the file system.
    public var locateDataRoot: () -> GameDataRoot? = { try? GameDataLocator.locate() }
    private var dataRoot: GameDataRoot?
    private var dataRootResolved = false

    private let menuMode: MenuModeController
    private let movies: SWFMovieSource
    let hud: HUDCoordinator
    weak let world: SystemMenuWorld?

    public init(
        menuMode: MenuModeController,
        movies: SWFMovieSource,
        hud: HUDCoordinator,
        settings: PlayerSettingsCoordinator,
        saves: SaveGameService?,
        world: SystemMenuWorld? = nil
    ) {
        self.menuMode = menuMode
        self.movies = movies
        self.hud = hud
        self.settings = settings
        self.saves = saves
        self.world = world
        settingsPage = SettingsPageModel(catalog: settings.store.catalog)
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
        get { Float(settings.store.value(.masterVolume)) }
        set { settings.store.set(.masterVolume, to: Double(newValue)) }
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
        case .commandLine: "command line"
        case .environment: "\(GameDataLocator.environmentKey) environment variable"
        case .userDefaults: "Settings"
        case .steamDefault: "Steam default"
        case .steamLibrary: "Steam library"
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
                SystemMenuMovieBridge.registerTopics(
                    runtime: runtime,
                    topics: { [weak self] page in self?.showTopicPage(page)?.topics ?? [] },
                    open: { [weak self] index in self?.openTopic(index) }
                )
                MenuMovieButtonArt.register(runtime: runtime) { [weak self] event in
                    self?.settings.buttonName(forUserEvent: event)
                }
            }
        ))
    }

    public var snapshot: SystemMenuControlSnapshot {
        SystemMenuControlSnapshot(
            dataRootPath: dataRootValue?.installURL.path(percentEncoded: false),
            dataRootSource: dataRootValue.map { Self.dataRootSourceLabel($0.source) },
            audioEnabled: world?.audioEnabled ?? false,
            movieEnabled: movieEnabled,
            page: pageSnapshot
        )
    }

    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "SystemMenu"
    )
}
