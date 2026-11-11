import OpenSkyActorPresentation
import OpenSkyActorsInterface
public import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyNavigation
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `AIPackageMovesAdapter` reads from the session.
@MainActor
public protocol AIPackageMovesHost: AnyObject, SendableMetatype {
    var dragonFlightWorld: any DragonFlightWorldPort { get }
    var furniture: any FurniturePort { get }
    var gameSession: (any GameSessionPort)? { get }
    var idleWorld: any IdleWorldPort { get }
    var packages: any PackagePort { get }
    var scripts: any ScriptPort { get }
    var streamer: any CellStreamerPort { get }
    var vehicleWorld: any VehicleWorldPort { get }
}

/// Part of `AIWorldAdapter`, over its own narrow host.
public struct AIPackageMovesAdapter {
    public let game: any AIPackageMovesHost
}

extension AIPackageMovesAdapter {
    public func packageActorPosition(_ actor: ReferenceKey) -> SIMD3<Float>? {
        guard actor != .player else { return game.gameSession?.locomotion.status.feetPosition }
        let streamer = game.streamer
        if let live = streamer.npcTransform(for: actor) {
            return live.position
        }
        return streamer.referenceEntry(key: actor).flatMap(Self.Places.placedPosition)
    }

    var packageDrivesPlayer: Bool {
        game.vehicleWorld.isPlayerAIDriven
    }

    public func packageActorHoldsIdleMarker(_ actor: ReferenceKey) -> Bool {
        game.idleWorld.idles.holdsMarker(actor)
    }

    /// A dragon outdoors flies its package's walks; indoors it walks them.
    public func packageActorFlies(_ actor: ReferenceKey) -> Bool {
        actor != .player && game.streamer.interiorScene == nil
            && game.dragonFlightWorld.actorFliesPackages(actor)
    }

    public func packageSandboxActivityEnded(_ activity: SandboxActivity, actor: ReferenceKey) {
        switch activity {
        case .idleMarker: game.idleWorld.idles.leaveMarker(actor)
        case .wandering: game.idleWorld.idles.allowPreviousMarker(actor)
        default: break
        }
    }

    public func movePackageActor(_ move: PackageMove) -> PackageMoveResult {
        let actor = move.actor
        if actor == .player {
            return walkPlayer(to: move.point, direct: move.direct) ? .started : .failed
        }
        // The exit clip carries the actor out of its seat first.
        if game.furniture.isLeavingSeat(actor) {
            return .busy
        }
        let result = game.streamer.moveActor(
            actor, to: move.point, direct: move.direct, gait: move.gait,
            runSlowdown: game.packages.followRunSlowdown(for: actor),
            walkRunBlend: move.walkRunBlend
        )
        game.packages.recordMove(result, for: actor)
        switch result {
        case .started: return .started
        case .moverCapReached: return .busy
        default: return .failed
        }
    }

    /// The player has no NPC mover, so the renderer walks the navmesh path. Without
    /// a path the player walks straight, as a direct move does.
    private func walkPlayer(to point: SIMD3<Float>, direct: Bool) -> Bool {
        guard let gameSession = game.gameSession else { return false }
        let query = NavigationPathQuery(
            start: gameSession.walkController.feetPosition, target: point,
            capsuleRadius: PlayerCapsule.standard.radius
        )
        gameSession.playerWalkIgnoresStatics = direct
        let found = direct ? NavigationPathResult.path(.straight(to: point))
            : game.streamer.findPath(query)
        switch found {
        case let .path(path):
            gameSession.playerWalkPath = path.waypoints + [point]
            game.packages.recordMove(.started, for: .player)
        case let .miss(reason):
            gameSession.playerWalkPath = [point]
            game.packages.recordMove(.noPath(reason), for: .player)
        }
        return true
    }

    public func packageProcedure(_ event: PackageScriptEvent) {
        game.scripts.bridge?.runPackageFragment(
            of: event.package, slot: event.fragmentSlot, actor: event.actor
        )
        game.scripts.bridge?.queuePackageEvent(
            slot: event.fragmentSlot, package: event.package.formID, actor: event.actor
        )
    }
}
