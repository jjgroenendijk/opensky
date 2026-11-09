// The game window and the game it runs. Agent control and the benchmark host both ask it,
// so they never disagree about the current game when a window opens, swaps, or closes.

import AppKit

/// What a game window shows: the game view controller in the app, a fake in a test.
@MainActor
protocol GameWindowContent: AnyObject {
    var onSessionStart: ((GameSessionScope) -> Void)? { get set }
}

@MainActor
final class GameWindowRegistry<Game: GameWindowContent> {
    private(set) var window: NSWindow?
    /// The game the window runs now; nil while no game window is open.
    private(set) var game: Game?
    /// Runs for each session the current game starts, with the window it shows in.
    private let sessionStarted: (GameSessionScope, NSWindow) -> Void

    init(sessionStarted: @escaping (GameSessionScope, NSWindow) -> Void) {
        self.sessionStarted = sessionStarted
    }

    func open(_ game: Game, in window: NSWindow) {
        self.window = window
        show(game)
    }

    /// A settings reload runs a new game in the open window.
    func switchGame(to game: Game) {
        guard window != nil else { return }
        show(game)
    }

    /// Returns the game that ran in the closed window.
    @discardableResult
    func close() -> Game? {
        let closed = game
        game = nil
        window = nil
        return closed
    }

    /// A game that was swapped out may still start its session; only the current one counts.
    private func show(_ game: Game) {
        self.game = game
        game.onSessionStart = { [weak self, weak game] session in
            guard let self, let game, self.game === game, let window else { return }
            sessionStarted(session, window)
        }
    }
}
