// App side of the smaller menu screens: wait and rest, training, books, help, magic,
// gifts, crafting, and text entry. Each coordinator holds its rules; this adapter
// only reads and writes the session for them.

import Foundation
import OpenSkyActors
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCrime
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld
import OpenSkyWorldState

/// What `MenuScreensWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol MenuScreensWorldHost: MenuInputConsumer {
    var actorValues: ActorValueCoordinator { get }
    var actorWorld: ActorWorldAdapter { get }
    var combat: CombatCoordinator { get }
    var crime: CrimeCoordinator { get }
    var gameSession: GameSession? { get }
    var hud: HUDCoordinator { get }
    var inventory: InventoryCoordinator { get }
    var inventoryWorld: InventoryWorldAdapter { get }
    var magic: MagicCoordinator { get }
    var mapWorld: MapWorldAdapter { get }
    var messageWorld: MessageWorldAdapter { get }
    var playerSettings: PlayerSettingsCoordinator { get }
    var progression: ProgressionCoordinator { get }
    var progressionWorld: ProgressionWorldAdapter { get }
    var renderer: Renderer? { get }
    var saveGames: SaveGameWorldAdapter { get }
    var scripts: ScriptCoordinator { get }
    var streamer: CellStreamer? { get }
    var worldData: WorldDataStores? { get }
}

final class MenuScreensWorldAdapter {
    unowned let game: any MenuScreensWorldHost

    init(game: any MenuScreensWorldHost) {
        self.game = game
    }

    var renderer: Renderer? {
        game.renderer
    }

    var viewCamera: FreeFlyCamera? {
        game.gameSession?.freeFlyCamera
    }

    var uiScene: UIScene {
        get { game.gameSession?.uiScene ?? .empty }
        set { game.gameSession?.uiScene = newValue }
    }

    var menuInputConsumer: (any MenuInputConsumer)? {
        game
    }

    func showHUDNotification(_ text: String) {
        game.hud.showNotification(text)
    }
}

extension MenuScreensWorldAdapter: SleepWaitWorld {
    var gameDateText: String? {
        game.gameSession?.gameClock.menuDateText
    }

    func restRefusal(sleeping: Bool, bed: FormID?) -> String? {
        var context = RestContext()
        let combat = game.combat.combatLoopSnapshot
        context.inCombat = combat.isPlayerInCombat
        context.hostilesNear = combat.hostileCount > 0
        context.alarmed = game.crime.isPlayerPursued
        context.trespassing = game.crime.isPlayerTrespassing
        context.warnedToLeave = game.crime.isPlayerWarnedToLeave
        if let bed, let key = game.streamer?.referenceEntry(formID: bed)?.key {
            // The theft rule decides whose a bed is, as it does for an item.
            context.bedOwnedByOther = game.crime.ownershipVerdict(on: key).isTheft
        }
        context.inAir = !(game.gameSession?.walkController.isGrounded ?? true)
        context.takingHealthDamage = game.magic.isPlayerTakingHealthDamage
        context.waitingDisabled = game.scripts.bridge?.playerControlLocks.waitingDisabled ?? false
        guard let refusal = RestRule.refusal(context) else { return nil }
        return game.mapWorld.settingTexts(RestText.self)[refusal.text(sleeping: sleeping)]
    }

    /// The clock moves in 15-minute steps. Each step ages the weather and runs the
    /// scripts' game-time timers; health, magicka, and stamina refill at the end.
    func passTime(hours: Int, sleeping: Bool) {
        guard let gameSession = game.gameSession else { return }
        let start = gameSession.gameClock
        for step in RestTimeSteps.steps(hours: hours) {
            gameSession.gameTime.clock = GameClock(
                totalGameSeconds: start.totalGameSeconds + step * GameClock.secondsPerHour
            )
            gameSession.updateWeather(deltaTime: 0)
            game.scripts.advance(delta: 0)
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
