import Foundation
import OpenSkyActorsInterface
import OpenSkyAgentControl
import OpenSkyAudio
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyLaunch
import OpenSkyLoading
import OpenSkyMagic
import OpenSkyMenus
public import OpenSkyMenusInterface
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkySave
import OpenSkySaveInterface
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `MenuWorldNewGameAdapter` reads from the session.
@MainActor
public protocol MenuWorldNewGameHost: AnyObject {
    var effectsWorld: any EffectsWorldPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var inventory: any InventoryPort { get }
    var messages: any MessageCoordinatorPort { get }
    var player: any PlayerPort { get }
    var saveGames: any SaveGameWorldPort { get }
    var scripts: any ScriptPort { get }
    var storyWorld: any StoryWorldPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `MenuWorldAdapter`, over its own narrow host.
public struct MenuWorldNewGameAdapter {
    public unowned let owner: MenuWorldAdapter
    public unowned let game: any MenuWorldNewGameHost
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
        owner.coverNextTeleport = true
        switch start {
        case .vanilla:
            owner.teleports.coverUntilFirstMove()
            if !game.storyWorld.startOpeningQuest() {
                owner.teleports.abandonNewGameCover()
            }
        case let .cell(editorID): owner.teleportPlayer(.cell(editorID), openingRaceMenu: true)
        }
    }

    public func holdWorldLoading() {
        game.streamer?.isHeld = true
    }

    public func quitApplication() {
        owner.terminateApp()
    }
}
