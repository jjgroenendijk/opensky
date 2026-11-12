// App side of the smaller menu screens: wait and rest, training, books, help, magic,
// gifts, crafting, and text entry. Each coordinator holds its rules; this adapter
// only reads and writes the session for them.

import Foundation
import OpenSkyActorsInterface
import OpenSkyCells
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
public import OpenSkyMenus
public import OpenSkyMenusInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
public import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `MenuScreensWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol MenuScreensWorldHost: MenuInputConsumer, SendableMetatype {
    var actorValues: any ActorValuePort { get }
    var combat: any CombatPort { get }
    var crime: any CrimePort { get }
    var gameSession: (any GameSessionPort)? { get }
    var hud: any HUDPort { get }
    var magic: any MagicPort { get }
    var mapWorld: any MapWorldPort { get }
    var runtimeState: any RuntimeStatePort { get }
    var renderer: (any RendererPort)? { get }
    var saveGames: any SaveGameWorldPort { get }
    var scripts: any ScriptPort { get }
    var streamer: any CellStreamerPort { get }
}

/// Every host a `MenuScreensWorldAdapter` part reads, all one object.
public typealias MenuScreensWorldHosts = MenuScreensCraftingDeskHost & MenuScreensGiftListsHost &
    MenuScreensGuidesHost & MenuScreensWorldHost

public final class MenuScreensWorldAdapter {
    public let game: any MenuScreensWorldHost

    let hosts: any MenuScreensWorldHosts

    public var craftingDesk: MenuScreensCraftingDeskAdapter {
        MenuScreensCraftingDeskAdapter(game: hosts
        )
    }

    public var guides: MenuScreensGuidesAdapter {
        MenuScreensGuidesAdapter(game: hosts)
    }

    public var giftLists: MenuScreensGiftListsAdapter {
        MenuScreensGiftListsAdapter(game: hosts
        )
    }

    public init(game: some MenuScreensWorldHosts) {
        hosts = game
        self.game = game
    }

    public var renderer: (any RendererPort)? {
        game.renderer
    }

    public var viewCamera: FreeFlyCamera? {
        game.gameSession?.freeFlyCamera
    }

    public var uiScene: UIScene {
        get { game.gameSession?.uiScene ?? .empty }
        set { game.gameSession?.uiScene = newValue }
    }

    public var menuInputConsumer: (any MenuInputConsumer)? {
        game
    }

    public func showHUDNotification(_ text: String) {
        game.hud.showNotification(text)
    }
}

extension MenuScreensWorldAdapter: SleepWaitWorld {
    public var gameDateText: String? {
        game.gameSession.map { game.runtimeState.dateLine(of: $0.gameClock) }
    }

    public func restRefusal(sleeping: Bool, bed: FormID?) -> String? {
        rest.restRefusal(sleeping: sleeping, bed: bed)
    }

    /// The clock moves in 15-minute steps. Each step ages the weather and runs the
    /// scripts' game-time timers; health, magicka, and stamina refill at the end.
    public func passTime(hours: Int, sleeping: Bool) {
        guard let gameSession = game.gameSession else { return }
        let start = gameSession.gameClock
        let timescale = Double(max(gameSession.currentTimescale, 1))
        for step in RestTimeSteps.steps(hours: hours) {
            let before = gameSession.gameClock.totalGameSeconds
            gameSession.gameTime.clock = GameClock(
                totalGameSeconds: start.totalGameSeconds + step * GameClock.secondsPerHour
            )
            gameSession.updateWeather(deltaTime: 0)
            game.scripts.advanceRestStep()
            // Effect durations are real seconds: game seconds over the timescale.
            let skipped = gameSession.gameClock.totalGameSeconds - before
            game.magic.frameStep.elapseRestTime(seconds: skipped / timescale)
        }
        if sleeping {
            game.scripts.reportSleep(
                start: Double(start.daysPassed), end: Double(gameSession.gameClock.daysPassed)
            )
        }
        game.actorValues.runtime?.restoreAll(on: .player)
        game.saveGames.autosave(sleeping ? .rest : .wait)
    }
}

extension MenuScreensWorldAdapter: MenuScreensWorldPort {}
