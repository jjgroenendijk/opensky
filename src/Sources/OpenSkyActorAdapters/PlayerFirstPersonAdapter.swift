import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyPhysics
public import OpenSkyPlayer
import OpenSkyRenderCore
public import OpenSkyRendering
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
    /// The app sees the session's concrete body and rig types.
    func setPlayerBody(_ body: PlayerBody) throws
    func setPlayerFirstPersonRig(_ rig: PlayerFirstPersonRig) throws
    var renderer: (any RendererPort)? { get }
}

/// Part of `PlayerWorldAdapter`, over its own narrow host.
public struct PlayerFirstPersonAdapter {
    public let game: any PlayerFirstPersonHost
    public let state: PlayerPartState
}

extension PlayerFirstPersonAdapter {
    /// The footstep set follows the boots of the assembly just built.
    public func showPlayerBody(_ body: PlayerBody) throws {
        game.audio.updateFootstepSet(feetArmatures: body.feetArmatures)
        try game.setPlayerBody(body)
    }

    public func showFirstPersonRig(_ rig: PlayerFirstPersonRig) throws {
        try game.setPlayerFirstPersonRig(rig)
    }

    public var playerFirstPersonRig: PlayerFirstPersonRig? {
        state.firstPersonRig()
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
