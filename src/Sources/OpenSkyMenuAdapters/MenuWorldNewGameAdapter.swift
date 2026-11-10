import Foundation
import OpenSkyActorsInterface
import OpenSkyAgentControl
import OpenSkyAudio
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyLaunch
import OpenSkyLoading
import OpenSkyMagicInterface
import OpenSkyMenus
public import OpenSkyMenusInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkySaveInterface
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `MenuWorldNewGameAdapter` reads from the session.
@MainActor
public protocol MenuWorldNewGameHost: AnyObject, SendableMetatype {
    var effectsWorld: any EffectsWorldPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var inventory: any InventoryPort { get }
    var messages: any MessageCoordinatorPort { get }
    var player: any PlayerPort { get }
    var saveGames: any SaveGameWorldPort { get }
    var scripts: any ScriptPort { get }
    var storyWorld: any StoryWorldPort { get }
    var streamer: any CellStreamerPort { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `MenuWorldAdapter`, over its own narrow host.
public struct MenuWorldNewGameAdapter {
    public let game: any MenuWorldNewGameHost
    public let state: MenuPartState
    public let teleports: MenuWorldTeleportsAdapter
}

extension MenuWorldNewGameAdapter {
    /// A fresh session: empty world state, the start clock, and the opening
    /// quests. The opening quest places the player and opens the race menu itself.
    /// A chosen cell is a test start, so the race menu opens there at once.
    public func startNewGame(at start: NewGameStart) {
        game.worldState.restore(from: .empty)
        game.inventory.registerCreatedPotions()
        game.gameSession?.gameClock = GameClock()
        game.gameSession?.clearScriptScreenEffects()
        game.effectsWorld.fadeOutHealthCues()
        game.scripts.restore(instances: [], timers: [])
        game.messages.reloadHelpRecords()
        game.storyWorld.rerunSessionStart()
        game.saveGames.resetPlayTime()
        game.player.refreshBody()
        state.coverNextTeleport = true
        switch start {
        case .vanilla:
            teleports.coverUntilFirstMove()
            if !game.storyWorld.startOpeningQuest() {
                teleports.abandonNewGameCover()
            }
        case let .cell(editorID): teleports.teleportPlayer(.cell(editorID), openingRaceMenu: true)
        }
    }

    public func holdWorldLoading() {
        game.streamer.isHeld = true
    }

    public func quitApplication() {
        state.terminateApp()
    }
}
