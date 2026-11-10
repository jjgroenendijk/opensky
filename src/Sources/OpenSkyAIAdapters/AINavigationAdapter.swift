public import OpenSkyActorPresentation
import OpenSkyActorsInterface
public import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
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

/// What `AINavigationAdapter` reads from the session.
@MainActor
public protocol AINavigationHost: AnyObject, SendableMetatype {
    var actorWorld: any ActorWorldPort { get }
    var factions: any FactionPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var npcAnimation: any NPCAnimationPort { get }
    var scripts: any ScriptPort { get }
    var animationClips: ActorClipLoader? { get }
    var streamer: any CellStreamerPort { get }
    var vehicleWorld: any VehicleWorldPort { get }
}

/// Part of `AIWorldAdapter`, over its own narrow host.
public struct AINavigationAdapter {
    public let game: any AINavigationHost
}

extension AINavigationAdapter {
    /// The rider's root sits on this node of the horse skeleton (docs/engine/vehicles.md).
    public static let saddleBone = "SaddleBone"

    /// The horse a placed actor starts on, `ACHR` `XHOR` (docs/formats/placed-references.md).
    public func mountPackageActor(_ rider: ReferenceKey) -> ReferenceKey? {
        guard
            let raw = game.streamer.placedRecords?.entry(for: rider)?.placedActor?
                .details.links["XHOR"],
            let resolver = game.scripts.bridge?.formIDResolver,
            let horse = ReferenceKey.resolve(raw, using: resolver),
            game.vehicleWorld.vehicles.seat(rider, on: horse, bone: Self.saddleBone)
        else { return nil }
        _ = game.streamer.stopActor(rider)
        game.npcAnimation.ride(rider, on: horse)
        return horse
    }

    /// The horse walked the rider's package, so it stops with it.
    public func dismountPackageActor(_ rider: ReferenceKey) {
        if let horse = vehicleCarrier(of: rider) {
            _ = game.streamer.stopActor(horse)
        }
        game.vehicleWorld.detach(rider)
        game.npcAnimation.dismount(rider)
    }

    public func vehicleCarrier(of actor: ReferenceKey) -> ReferenceKey? {
        game.vehicleWorld.vehicles.core.links[actor]?.carrier
    }

    var camera: AICameraPose? {
        game.gameSession.map {
            AICameraPose(position: $0.freeFlyCamera.position, forward: $0.freeFlyCamera.forward)
        }
    }

    public func actorCandidates() -> [AIActorCandidate] {
        game.actorWorld.combatActors().map {
            AIActorCandidate(key: $0.key, name: $0.name, feet: $0.feet)
        }
    }

    public func nearestCollisionHit(ray: InteractionRay) -> InteractionRayHit? {
        game.streamer.nearestCollisionHit(ray: ray)
    }

    public func residentActor(for reference: FormID) -> ReferenceKey? {
        game.streamer.residentActorEntries().first { $0.formID == reference }?.key
    }

    public func moveActor(_ actor: ReferenceKey, to point: SIMD3<Float>) -> NPCMoveCommandResult {
        game.streamer.moveActor(actor, to: point)
    }

    public func stopActor(_ actor: ReferenceKey) -> Bool {
        game.streamer.stopActor(actor)
    }

    public func isHostile(_ actor: ReferenceKey) -> Bool {
        game.factions.hostility(of: actor) == .hostile
    }

    public func setHostile(_ hostile: Bool, actor: ReferenceKey) {
        game.factions.setHostility(hostile ? .hostile : .neutral, on: actor)
    }

    var animationClips: ActorClipLoader? {
        game.animationClips
    }
}
