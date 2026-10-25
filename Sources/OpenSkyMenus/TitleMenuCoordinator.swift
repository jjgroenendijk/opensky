// The title menu: Continue, New, Load, and Quit over a held world. It shows
// the vanilla main menu movie when it loads; see docs/engine/main-menu.md.

import Foundation
import OpenSkyGameData
import OpenSkyRendering

/// What the title menu does in the running game.
public protocol TitleMenuWorld: AnyObject {
    var menuInputConsumer: (any MenuInputConsumer)? { get }
    var renderer: Renderer? { get }
    /// Shows the logo scene in place of the world, as the game does.
    func showTitleBackdrop(_ shown: Bool)
    /// Loads no world until the player picks a start, because a save can be in another world.
    func holdWorldLoading()
    /// Clears the session, starts the opening quests, and places the player.
    func startNewGame(at start: NewGameStart)
    func quitApplication()
    /// The install's files, for the credits text; nil without game data.
    var gameFiles: (any GameFileSource)? { get }
}

/// Where a new game puts the player.
nonisolated public enum NewGameStart: Equatable, Sendable {
    /// The vanilla opening: the opening quest moves the player and opens the race menu.
    case vanilla
    /// A cell by editor ID, for testing. The race menu opens at once.
    case cell(String)

    /// The game starts this quest on a new game by name: it is not start-game
    /// enabled and no `.seq` file lists it (docs/engine/main-menu.md).
    public static let openingQuest = "MQ101"
}

nonisolated public enum TitleMenuEntry: String, CaseIterable, Sendable {
    case resume = "Continue"
    case new = "New"
    case load = "Load"
    case quit = "Quit"
}

nonisolated public struct TitleMenuSnapshot: Equatable, Sendable {
    public let rows: [String]
    public let selectedIndex: Int
    public let isLoadPageOpen: Bool
    public let lastResult: String?
    public let movie: TitleMenuMovieSnapshot

    public init(
        rows: [String],
        selectedIndex: Int,
        isLoadPageOpen: Bool,
        lastResult: String?,
        movie: TitleMenuMovieSnapshot = TitleMenuMovieSnapshot()
    ) {
        self.rows = rows
        self.selectedIndex = selectedIndex
        self.isLoadPageOpen = isLoadPageOpen
        self.lastResult = lastResult
        self.movie = movie
    }
}

nonisolated public struct TitleMenuMovieSnapshot: Equatable, Sendable {
    public let isLoaded: Bool
    public let error: String?
    public let rows: [String]
    public let selectedIndex: Int?
    public let state: String?

    public init(
        isLoaded: Bool = false,
        error: String? = nil,
        rows: [String] = [],
        selectedIndex: Int? = nil,
        state: String? = nil
    ) {
        self.isLoaded = isLoaded
        self.error = error
        self.rows = rows
        self.selectedIndex = selectedIndex
        self.state = state
    }
}

public final class TitleMenuCoordinator {
    public static let identifier: MenuIdentifier = "Main Menu"

    public private(set) var isOpen = false
    public private(set) var selectedIndex = 0
    public private(set) var loadPage: SaveLoadPageModel?
    public internal(set) var lastResult: String?
    public weak let saves: SaveGameService?
    /// The movie is the menu the player sees; the engine rows stay the fallback.
    public private(set) var movieEnabled = true
    /// The credits movie has the layer in place of the title movie.
    public internal(set) var creditsShown = false
    /// The credits movie asked to close; applied after its step.
    var creditsClosing = false
    /// A row the movie picked during input, applied once the movie returns.
    var pendingRequest: TitleMenuMovieBridge.Request?
    /// Load list calls from the movie, answered once its input event ends.
    var pendingLoadCalls: [TitleMenuLoadBridge.Call] = []
    var framePacer = MenuMovieFramePacer()
    /// The saves of the character picked in the movie's Load list.
    var loadListRows: [SaveSlotRow] = []
    /// The running load; one at a time.
    public private(set) var loadWork: Task<Void, Never>?
    /// Reads the save list, then starts the movie.
    private(set) var openWork: Task<Void, Never>?
    private let menuMode: MenuModeController
    let movies: SWFMovieSource?
    let hud: HUDCoordinator?
    weak let world: (any TitleMenuWorld)?

    public init(
        menuMode: MenuModeController, movies: SWFMovieSource? = nil, hud: HUDCoordinator? = nil,
        saves: SaveGameService?, world: (any TitleMenuWorld)? = nil
    ) {
        self.menuMode = menuMode
        self.saves = saves
        self.movies = movies
        self.hud = hud
        self.world = world
    }

    lazy var movie = MenuMovieSession(
        movies: movies, hud: hud, label: "title movie", logger: Self.movieLogger
    ) { [weak self] in self?.world?.renderer }

    public var movieLoaded: Bool {
        movie.isLoaded
    }

    public var movieError: String? {
        movie.error
    }

    /// Continue shows only when an OpenSky save exists, once the list has been read.
    /// It never picks an import.
    public var entries: [TitleMenuEntry] {
        let hasSaves = saves?.saveRows.contains { !$0.isImport } ?? false
        return TitleMenuEntry.allCases.filter { $0 != .resume || hasSaves }
    }

    public func open() {
        guard !isOpen else { return }
        isOpen = true
        selectedIndex = 0
        loadPage = nil
        menuMode.inputConsumer = world?.menuInputConsumer
        menuMode.present(Self.identifier)
        world?.holdWorldLoading()
        guard let saves else {
            if movieEnabled {
                startMovie()
            }
            return
        }
        // The movie reads Continue and Load from the save list once, at start.
        openWork = Task {
            let rows = await saves.refreshSaveRows()
            self.loadPage?.replaceRows(rows)
            if self.isOpen, self.movieEnabled, !self.movieLoaded {
                self.startMovie()
            }
        }
    }

    public func close() {
        guard isOpen else { return }
        isOpen = false
        loadPage = nil
        creditsShown = false
        creditsClosing = false
        menuMode.dismiss(Self.identifier)
        stopMovie()
    }

    public func route(_ event: MenuInputEvent) {
        guard isOpen else { return }
        if loadPage != nil {
            routeLoad(event)
            return
        }
        if creditsShown {
            routeCredits(event)
            return
        }
        if movieLoaded, let renderer = world?.renderer {
            routeMovie(event, renderer: renderer)
            return
        }
        let count = entries.count
        switch event {
        case .move(.up): selectedIndex = (selectedIndex + count - 1) % count
        case .move(.down): selectedIndex = (selectedIndex + 1) % count
        case .button(.accept): activate(entries[min(selectedIndex, count - 1)])
        default: break
        }
    }

    func activate(_ entry: TitleMenuEntry) {
        switch entry {
        case .resume:
            guard
                let newest = saves?.saveRows.filter({ !$0.isImport })
                    .max(by: { $0.savedAt < $1.savedAt })
            else { return }
            load(newest.slot)
        case .new:
            newGame(at: .vanilla)
        case .load:
            loadPage = SaveLoadPageModel(mode: .load, rows: saves?.saveRows ?? [])
            refreshSaveRows()
        case .quit:
            world?.quitApplication()
        }
    }

    public func newGame(at start: NewGameStart) {
        close()
        world?.startNewGame(at: start)
        switch start {
        case .vanilla: lastResult = "New game"
        case let .cell(editorID): lastResult = "New game at \(editorID)"
        }
    }

    private func routeLoad(_ event: MenuInputEvent) {
        guard var page = loadPage else { return }
        let action = page.handle(event)
        loadPage = page
        switch action {
        case let .load(slot): load(slot)
        case .back: loadPage = nil
        default: break
        }
    }

    public func load(_ slot: String) {
        guard let saves, loadWork == nil else { return }
        lastResult = "Loading \(slot)"
        loadWork = Task {
            do {
                try await saves.loadGame(slot: slot)
                self.close()
                self.lastResult = "Loaded \(slot)"
            } catch {
                self.lastResult = "Load failed: \(error)"
            }
            self.loadWork = nil
        }
    }

    private func refreshSaveRows() {
        guard let saves else { return }
        Task {
            let rows = await saves.refreshSaveRows()
            self.loadPage?.replaceRows(rows)
        }
    }

    public var snapshot: TitleMenuSnapshot {
        let runtime = movie.runtime
        return TitleMenuSnapshot(
            rows: loadPage?.titles ?? entries.map(\.rawValue),
            selectedIndex: loadPage?.selectedIndex ?? selectedIndex,
            isLoadPageOpen: loadPage != nil,
            lastResult: lastResult,
            movie: TitleMenuMovieSnapshot(
                isLoaded: movieLoaded,
                error: movieError,
                rows: runtime.map(TitleMenuMovieBridge.entryLabels(runtime:)) ?? [],
                selectedIndex: runtime.flatMap(TitleMenuMovieBridge.selectedIndex(runtime:)),
                state: runtime.flatMap(TitleMenuMovieBridge.currentState(runtime:))
            )
        )
    }
}
