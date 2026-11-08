import Foundation
import OpenSkyActors
import OpenSkyCamera
public import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMagic
public import OpenSkyMenus
public import OpenSkyMenusInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyQuests
import OpenSkyQuestsInterface
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `MapTravelAdapter` reads from the session.
@MainActor
public protocol MapTravelHost: AnyObject {
    var actorValues: any ActorValuePort { get }
    var combat: any CombatPort { get }
    var crime: any CrimePort { get }
    var gameSession: (any GameSessionPort)? { get }
    var inventory: any InventoryPort { get }
    var loadingWorld: any LoadingScreenWorldPort { get }
    var magic: any MagicPort { get }
    var renderer: (any RendererPort)? { get }
    var saveGames: any SaveGameWorldPort { get }
    var scripts: any ScriptPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var worldData: WorldDataStores? { get }
}

/// Part of `MapWorldAdapter`, over its own narrow host.
public struct MapTravelAdapter {
    public unowned let owner: MapWorldAdapter
    public unowned let game: any MapTravelHost
}

extension MapTravelAdapter {
    public var fastTravelContext: FastTravelContext {
        var context = FastTravelContext()
        let combat = game.combat.combatLoopSnapshot
        context.inCombat = combat.isPlayerInCombat
        context.hostilesNear = combat.hostileCount > 0
        context.inAir = !(game.gameSession?.walkController.isGrounded ?? true)
        context.alarmed = game.crime.isPlayerPursued
        context.takingHealthDamage = game.magic.isPlayerTakingHealthDamage
        if game.inventory.runtime != nil {
            context.overencumbered = FastTravelRule.isOverencumbered(
                carried: game.inventory.playerCarriedWeight,
                capacity: game.actorValues.runtime?.value(
                    at: ActorValueIdentity.carryWeightIndex, on: .player
                )
            )
        }
        return context
    }

    /// The trip takes game time for the walk, then lands at the marker.
    public func travel(to marker: MapMarkerSite) -> Bool {
        guard
            let renderer = game.renderer, let gameSession = game.gameSession,
            let streamer = game.streamer else { return false }
        let from = gameSession.walkController.feetPosition
        let walk = game.worldData?
            .movementConfiguration.travelSpeed.value ?? PlayerMovementConfiguration
            .fallbackTravelSpeed
        let seconds = FastTravelRule.gameSeconds(
            distance: simd_distance(from, marker.position), walkSpeed: walk,
            speedMultiplier: owner.mapSettings.fastTravelSpeedMultiplier,
            timeScale: gameSession.currentTimescale
        )
        gameSession
            .gameClock = GameClock(totalGameSeconds: gameSession.gameClock
                .totalGameSeconds + seconds)
        // The game shows a loading screen for every fast travel.
        game.loadingWorld.coverMove(to: marker.position)
        let rotation = SIMD3<Float>(0, 0, gameSession.freeFlyCamera.yaw)
        let camera = SceneCamera.teleport(placement: .init(
            position: marker.position,
            rotation: rotation
        ))
        // The markers belong to the map's worldspace, which can be the current one's parent.
        if let world = owner.mapWorldspace?.editorID, world != streamer.worldspaceEditorID {
            streamer.enterWorldspace(world, camera: camera)
        } else if streamer.interiorScene != nil {
            streamer.leaveInterior(camera: camera)
        } else {
            renderer.camera = camera
            gameSession.reseedMovement(camera: camera)
        }
        game.scripts.runtime?
            .queuePlayerFastTravelEnd(gameHours: Float(seconds / GameClock.secondsPerHour))
        game.saveGames.autosave(.travel)
        return true
    }
}
