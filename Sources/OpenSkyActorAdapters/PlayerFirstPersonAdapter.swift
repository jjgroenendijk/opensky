import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyPhysics
public import OpenSkyPlayer
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkySession
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `PlayerFirstPersonAdapter` reads from the session.
@MainActor
public protocol PlayerFirstPersonHost: AnyObject {
    var audio: any AudioPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var renderer: (any RendererPort)? { get }
}

/// Part of `PlayerWorldAdapter`, over its own narrow host.
public struct PlayerFirstPersonAdapter {
    public unowned let owner: PlayerWorldAdapter
    public unowned let game: any PlayerFirstPersonHost
}

extension PlayerFirstPersonAdapter {
    /// The footstep set follows the boots of the assembly just built.
    public func showPlayerBody(_ body: PlayerBody) throws {
        game.audio.updateFootstepSet(feetArmatures: body.feetArmatures)
        try game.gameSession?.setPlayerBody(body)
    }

    public func showFirstPersonRig(_ rig: PlayerFirstPersonRig) throws {
        try game.gameSession?.setPlayerFirstPersonRig(rig)
    }

    public var playerFirstPersonRig: PlayerFirstPersonRig? {
        owner.firstPersonRig()
    }

    public var areFirstPersonArmsVisible: Bool {
        game.renderer?.areFirstPersonArmsVisible ?? false
    }

    public var firstPersonFOVYRadians: Float? {
        game.gameSession?.firstPersonCamera.fovYRadians
    }

    public func setFirstPersonFOVY(radians: Float) {
        game.gameSession?.setFirstPersonFOVY(radians: radians)
    }

    public var firstPersonArmsEnabled: Bool? {
        game.gameSession?.firstPersonArmsEnabled
    }

    public func setFirstPersonArmsEnabled(_ enabled: Bool) {
        game.gameSession?.firstPersonArmsEnabled = enabled
    }
}
