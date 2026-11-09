// The window registry answers one current game, and only that game's session reaches
// the benchmark host, when a window opens, swaps its game, and closes.

import AppKit
@testable import OpenSky
@testable import OpenSkyCells
import OpenSkyWorldFixtures
import OpenSkyWorldTesting
import Testing

@MainActor
struct GameWindowRegistryTests {
    private final class FakeGame: GameWindowContent {
        var onSessionStart: ((GameSessionScope) -> Void)?

        func startSession() {
            onSessionStart?(GameSessionScope(
                worldData: nil,
                cellRunner: nil,
                gameSession: nil,
                streamer: CellStreamerFixture.makeStreamer(runner: ManualCellBuildRunner()),
                services: GameAppServices()
            ))
        }
    }

    private final class Started {
        var windows: [NSWindow] = []
    }

    private static func registry(_ started: Started) -> GameWindowRegistry<FakeGame> {
        GameWindowRegistry { _, window in started.windows.append(window) }
    }

    @Test func openingAWindowMakesItsGameCurrent() {
        let started = Started()
        let registry = Self.registry(started)
        let window = NSWindow()
        let game = FakeGame()
        registry.open(game, in: window)
        game.startSession()
        #expect(registry.game === game)
        #expect(registry.window === window)
        #expect(started.windows.count == 1)
        #expect(started.windows.first === window)
    }

    @Test func aSwappedOutGameNoLongerReachesTheHost() {
        let started = Started()
        let registry = Self.registry(started)
        let window = NSWindow()
        let first = FakeGame()
        let second = FakeGame()
        registry.open(first, in: window)
        registry.switchGame(to: second)
        first.startSession()
        #expect(registry.game === second)
        #expect(started.windows.isEmpty)
        second.startSession()
        #expect(started.windows.count == 1)
    }

    @Test func closingTheWindowLeavesNoCurrentGame() {
        let started = Started()
        let registry = Self.registry(started)
        let game = FakeGame()
        registry.open(game, in: NSWindow())
        #expect(registry.close() === game)
        game.startSession()
        #expect(registry.game == nil)
        #expect(registry.window == nil)
        #expect(started.windows.isEmpty)
        registry.switchGame(to: FakeGame())
        #expect(registry.game == nil)
    }
}
