import Foundation
import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyAIPackages
public import OpenSkyAudio
public import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyDialogue
import OpenSkyFactions
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyPerception
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkySave
public import OpenSkySaveInterface
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
public import OpenSkyWorldState

/// What `RuntimeStateSessionClockAdapter` reads from the session.
@MainActor
public protocol RuntimeStateSessionClockHost: AnyObject {
    var gameSession: (any GameSessionPort)? { get }
    var hud: any HUDPort { get }
    var scripts: any ScriptPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var worldData: WorldDataStores? { get }
}

/// Part of `RuntimeStateWorldAdapter`, over its own narrow host.
public struct RuntimeStateSessionClockAdapter {
    public unowned let game: any RuntimeStateSessionClockHost
}

extension RuntimeStateSessionClockAdapter {
    public func referenceEntry(formID: FormID) -> RuntimeReferenceEntry? {
        game.streamer?.referenceEntry(formID: formID)
    }

    public var crosshairReference: FormID? {
        game.hud.interactionTarget?.interaction.reference
    }

    public var gameClock: GameClock? {
        get { game.gameSession?.gameClock }
        nonmutating set {
            // Setting the clock also resets the weather's elapsed-hours mark, so
            // a date jump ages no weather.
            if let newValue {
                game.gameSession?.gameClock = newValue
            }
        }
    }

    public var timescale: Float? {
        game.gameSession?.currentTimescale
    }

    public func setTimeOfDay(_ hour: Float) {
        game.gameSession?.timeOfDay = hour
    }

    public func persistTimeOfDay(_ hour: Float) {
        TimeOfDaySettings.store(hour)
    }

    public func projectTimeGlobal(_ global: GameClock.TimeGlobal, value: Float) -> Float? {
        guard let gameSession = game.gameSession else { return nil }
        let previous = gameSession.gameClock.projectedValue(global)
        gameSession.gameTime.clock.setProjectedValue(value, for: global)
        return previous
    }

    public func applyGlobalResolution(_ resolution: GlobalResolution, reroll: Bool) {
        guard let gameSession = game.gameSession else { return }
        gameSession.gameTime.globalResolution = resolution
        gameSession.weather?.setGlobalResolution(resolution, reroll: reroll)
        game.scripts.bridge?.publishLeveledEdits()
    }

    public var musicStore: MusicRecordStore? {
        game.worldData?.musicStore
    }

    public var globalStore: GlobalStore? {
        game.worldData?.globalStore
    }

    /// Interior coordinates are local to the cell, as the camera holds them there.
    /// The restore stands the player at these feet, so fly mode saves the camera.
    public func playerPlace() -> SavePlayerPlace? {
        guard
            let streamer = game.streamer, let cell = streamer.currentCellLocation,
            let gameSession = game.gameSession
        else { return nil }
        let feet = gameSession.movementMode.isPlayerControlled
            ? gameSession.walkController.feetPosition : gameSession.freeFlyCamera.position
        let worldspace: String? = switch cell {
        case .exterior: streamer.worldspaceEditorID
        case .interior: nil
        }
        return SavePlayerPlace(
            cell: cell, feet: feet, yaw: gameSession.freeFlyCamera.yaw, worldspace: worldspace
        )
    }
}
