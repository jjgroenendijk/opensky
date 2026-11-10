import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyCrime
import OpenSkyCrimeInterface
import OpenSkyDialogue
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyRenderCore
public import OpenSkyRendering
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `CrimeJailAdapter` reads from the session.
@MainActor
public protocol CrimeJailHost: AnyObject, SendableMetatype {
    var gameSession: (any GameSessionPort)? { get }
    var inventory: any InventoryPort { get }
    var inventoryWorld: any InventoryWorldPort { get }
    var progression: any ProgressionPort { get }
    var renderer: (any RendererPort)? { get }
    var streamer: any CellStreamerPort { get }
}

/// Part of `CrimeWorldAdapter`, over its own narrow host.
public struct CrimeJailAdapter {
    public let game: any CrimeJailHost
}

extension CrimeJailAdapter {
    var gameSeconds: Double? {
        game.gameSession?.gameClock.totalGameSeconds
    }

    var hourOfDay: Float? {
        game.gameSession?.gameClock.hourOfDay
    }

    public func passGameTime(days: Int) {
        guard let gameSession = game.gameSession else { return }
        gameSession.gameClock = GameClock(
            totalGameSeconds: gameSession.gameClock.totalGameSeconds
                + Double(days) * GameClock.secondsPerDay
        )
    }

    var playerFeet: SIMD3<Float>? {
        game.gameSession?.locomotion.status.feetPosition
    }

    public func enterJail(through marker: ReferenceKey) -> Bool {
        let streamer = game.streamer
        guard
            let door = streamer.pluginPlacement(of: marker)?.entry
            ?? streamer.referenceEntry(key: marker),
            door.placedReference?.teleportDestination != nil
        else { return false }
        return streamer.requestDoorTransition(from: door.formID)
    }

    /// The cell's PrisonMarker is the `XTEL` target of the outside one.
    public func leaveJail(to marker: ReferenceKey) -> Bool {
        let streamer = game.streamer
        guard
            let outside = streamer.pluginPlacement(of: marker)?.entry,
            let inside = outside.placedReference?.teleportDestination?.door
        else { return false }
        return streamer.requestDoorTransition(from: inside)
    }

    public func wearJailOutfit(_ outfit: FormID) -> [FormID] {
        guard
            let inventory = game.inventory.runtime?.inventory,
            let pieces = inventory.baselines.outfitStacks(
                outfit, roll: inventory.roll(of: .player)
            ),
            game.inventoryWorld.setOutfit(outfit, on: .player)
        else { return [] }
        return pieces.map(\.item)
    }

    public func loseJailProgress(days: Int, maximumDays: Int) -> Int {
        game.progression.loseJailProgress(days: days, maximumDays: maximumDays).count
    }

    var lockpickItem: FormID? {
        game.inventory.locks.lockpickItem
    }

    public func movePlayer(toMarker marker: ReferenceKey) -> Bool {
        guard
            let renderer = game.renderer, let gameSession = game.gameSession,
            let placement = game.streamer.referenceEntry(key: marker)?.placedReference?.placement
        else { return false }
        let camera = SceneCamera.teleport(placement: placement)
        renderer.camera = camera
        gameSession.reseedMovement(camera: camera)
        return true
    }
}
