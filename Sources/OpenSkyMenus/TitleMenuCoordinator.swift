// The title menu: Continue, New, Load, and Quit over a paused world. It shows
// the vanilla main menu movie when it loads; see docs/engine/main-menu.md.

import Foundation
import OpenSkyRendering

/// What the title menu does in the running game.
public protocol TitleMenuWorld: AnyObject {
    var menuInputConsumer: (any MenuInputConsumer)? { get }
    var renderer: Renderer? { get }
    /// Shows the logo scene in place of the world, as the game does.
    func showTitleBackdrop(_ shown: Bool)
    /// Clears the session, starts the opening quests, and opens the race menu.
    func startNewGame()
    func quitApplication()
}

nonisolated public enum TitleMenuEntry: String, CaseIterable, Sendable {
    case resume = "Continue"
    case new = "New"
    case load = "Load"
    case quit = "Quit"
}

nonisolated public struct TitleMenuSnapshot: Equatable, Sendable {
    public let isOpen: Bool
    public let rows: [String]
    public let selectedIndex: Int
    public let isLoadPageOpen: Bool
    public let lastResult: String?
    public let movie: TitleMenuMovieSnapshot

    public init(
        isOpen: Bool, rows: [String], selectedIndex: Int, isLoadPageOpen: Bool,
        lastResult: String?, movie: TitleMenuMovieSnapshot = TitleMenuMovieSnapshot()
    ) {
        self.isOpen = isOpen
        self.rows = rows
        self.selectedIndex = selectedIndex
        self.isLoadPageOpen = isLoadPageOpen
        self.lastResult = lastResult
        self.movie = movie
    }
}

nonisolated public struct TitleMenuMovieSnapshot: Equatable, Sendable {
    public let isEnabled: Bool
    public let isLoaded: Bool
    public let error: String?
    public let rows: [String]
    public let state: String?

    public init(
        isEnabled: Bool = false, isLoaded: Bool = false, error: String? = nil,
        rows: [String] = [], state: String? = nil
    ) {
        self.isEnabled = isEnabled
        self.isLoaded = isLoaded
        self.error = error
        self.rows = rows
        self.state = state
    }
}

public protocol TitleMenuControlProviding: AnyObject {
    /// Gives keyboard focus back to the game view after a panel button.
    func refocusGameView()
    var titleMenuSnapshot: TitleMenuSnapshot { get }
    func openTitleMenu()
    func closeTitleMenu()
    func sendTitleMenuInput(_ event: MenuInputEvent)
    func setTitleMenuMovieEnabled(_ enabled: Bool)
}

public final class TitleMenuCoordinator {
    public static let identifier: MenuIdentifier = "Main Menu"

    public private(set) var isOpen = false
    public private(set) var selectedIndex = 0
    public private(set) var loadPage: SaveLoadPageModel?
    public internal(set) var lastResult: String?
    public weak var saves: SaveGameService?
    /// The movie is the menu the player sees; the engine rows stay the fallback.
    public private(set) var movieEnabled = true
    public internal(set) var movieLoaded = false
    /// Bumped by each open and close, so a movie decoded late opens only the newest.
    var movieRequest = 0
    public internal(set) var movieError: String?
    /// A row the movie picked during input, applied once the movie returns.
    var pendingRequest: TitleMenuMovieBridge.Request?
    /// The running load; one at a time.
    public private(set) var loadWork: Task<Void, Never>?
    private let menuMode: MenuModeController
    let movies: SWFMovieSource?
    let hud: HUDCoordinator?
    private(set) weak var world: (any TitleMenuWorld)?

    public init(
        menuMode: MenuModeController, movies: SWFMovieSource? = nil, hud: HUDCoordinator? = nil
    ) {
        self.menuMode = menuMode
        self.movies = movies
        self.hud = hud
    }

    public func attach(world: any TitleMenuWorld) {
        self.world = world
    }

    /// Continue shows only when a save exists, once the save list has been read.
    public var entries: [TitleMenuEntry] {
        let hasSaves = !(saves?.saveRows.isEmpty ?? true)
        return TitleMenuEntry.allCases.filter { $0 != .resume || hasSaves }
    }

    public func open() {
        guard !isOpen else { return }
        isOpen = true
        selectedIndex = 0
        loadPage = nil
        menuMode.inputConsumer = world?.menuInputConsumer
        menuMode.present(Self.identifier)
        if movieEnabled {
            startMovie()
        }
        refreshSaveRows()
    }

    public func close() {
        guard isOpen else { return }
        isOpen = false
        loadPage = nil
        menuMode.dismiss(Self.identifier)
        if movieLoaded {
            stopMovie()
        }
    }

    public func setMovieEnabled(_ enabled: Bool) {
        guard enabled != movieEnabled else { return }
        movieEnabled = enabled
        guard isOpen else { return }
        if enabled {
            startMovie()
        } else {
            stopMovie()
        }
    }

    public func route(_ event: MenuInputEvent) {
        guard isOpen else { return }
        if loadPage != nil {
            routeLoad(event)
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
            guard let newest = saves?.saveRows.max(by: { $0.savedAt < $1.savedAt })
            else { return }
            load(newest.slot)
        case .new:
            close()
            world?.startNewGame()
            lastResult = "New game"
        case .load:
            loadPage = SaveLoadPageModel(mode: .load, rows: saves?.saveRows ?? [])
            refreshSaveRows()
        case .quit:
            world?.quitApplication()
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

    private func load(_ slot: String) {
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
        let runtime = movieLoaded ? world?.renderer?.swfRuntime : nil
        return TitleMenuSnapshot(
            isOpen: isOpen,
            rows: loadPage?.titles ?? entries.map(\.rawValue),
            selectedIndex: loadPage?.selectedIndex ?? selectedIndex,
            isLoadPageOpen: loadPage != nil,
            lastResult: lastResult,
            movie: TitleMenuMovieSnapshot(
                isEnabled: movieEnabled,
                isLoaded: movieLoaded,
                error: movieError,
                rows: runtime.map(TitleMenuMovieBridge.entryLabels(runtime:)) ?? [],
                state: runtime.flatMap(TitleMenuMovieBridge.currentState(runtime:))
            )
        )
    }
}

/// Lets the app's provider object stand in for its `TitleMenuCoordinator`.
public protocol TitleMenuControlForwarding: TitleMenuControlProviding {
    var titleMenu: TitleMenuCoordinator { get }
}

extension TitleMenuControlForwarding {
    public var titleMenuSnapshot: TitleMenuSnapshot {
        titleMenu.snapshot
    }

    public func openTitleMenu() {
        titleMenu.open()
    }

    public func closeTitleMenu() {
        titleMenu.close()
    }

    public func sendTitleMenuInput(_ event: MenuInputEvent) {
        titleMenu.route(event)
    }

    public func setTitleMenuMovieEnabled(_ enabled: Bool) {
        titleMenu.setMovieEnabled(enabled)
    }
}
