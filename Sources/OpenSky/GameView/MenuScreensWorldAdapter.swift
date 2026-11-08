// App side of the smaller menu screens: wait and rest, training, books, help, magic,
// gifts, crafting, and text entry. Each coordinator holds its rules; this adapter
// only reads and writes the session for them.

import Foundation
import OpenSkyActors
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyCrime
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `MenuScreensWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol MenuScreensWorldHost: MenuInputConsumer {
    var actorValues: any ActorValuePort { get }
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var crime: any CrimePort { get }
    var gameSession: (any GameSessionPort)? { get }
    var hud: any HUDPort { get }
    var inventory: any InventoryPort { get }
    var inventoryWorld: any InventoryWorldPort { get }
    var magic: any MagicPort { get }
    var mapWorld: any MapWorldPort { get }
    var messageWorld: any MessageWorldPort { get }
    var playerSettings: any PlayerSettingsPort { get }
    var progression: any ProgressionPort { get }
    var runtimeState: any RuntimeStatePort { get }
    var progressionWorld: any ProgressionWorldPort { get }
    var renderer: (any RendererPort)? { get }
    var saveGames: any SaveGameWorldPort { get }
    var scripts: any ScriptPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var worldData: WorldDataStores? { get }
}

final class MenuScreensWorldAdapter {
    unowned let game: any MenuScreensWorldHost

    init(game: any MenuScreensWorldHost) {
        self.game = game
    }

    var renderer: (any RendererPort)? {
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
        game.gameSession.map { game.runtimeState.dateLine(of: $0.gameClock) }
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
        context.cellForbidsWaiting = game.streamer?.currentCellLocation
            .flatMap { game.streamer?.residentScene(at: $0)?.forbidsWaiting } ?? false
        guard let refusal = RestRule.refusal(context) else { return nil }
        return game.mapWorld.settingTexts(RestText.self)[refusal.text(sleeping: sleeping)]
    }

    /// The clock moves in 15-minute steps. Each step ages the weather and runs the
    /// scripts' game-time timers; health, magicka, and stamina refill at the end.
    func passTime(hours: Int, sleeping: Bool) {
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
            game.magic.elapseRestTime(seconds: skipped / timescale)
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
