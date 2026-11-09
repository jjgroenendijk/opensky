import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyCells
public import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyCrimeInterface
import OpenSkyEffects
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
public import OpenSkyPhysics
import OpenSkyPlayer
public import OpenSkyRendering
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
public import simd

/// What `RagdollPoseReadsAdapter` reads from the session.
@MainActor
public protocol RagdollPoseReadsHost: AnyObject {
    func actorPlayback(for key: ReferenceKey) -> (any ActorAnimationPlaybackPort)?
    var actorValues: any ActorValuePort { get }
    func animatedPose(for key: ReferenceKey) -> [String: float4x4]?
    var gameSession: (any GameSessionPort)? { get }
    var renderer: (any RendererPort)? { get }
    var streamer: (any CellStreamerPort)? { get }
}

/// Part of `RagdollWorldAdapter`, over its own narrow host.
public struct RagdollPoseReadsAdapter {
    public let game: any RagdollPoseReadsHost
}

extension RagdollPoseReadsAdapter {
    public var ragdollResidents: [RagdollResident] {
        guard let streamer = game.streamer else { return [] }
        return streamer.residentActorEntries().compactMap { entry in
            entry.placedActor.map {
                RagdollResident(key: entry.key, position: $0.placement.position)
            }
        }
    }

    public var residentRagdollCells: Set<CellSceneLocation> {
        game.streamer?.residentCellLocations ?? []
    }

    public func hasZeroHealth(_ key: ReferenceKey) -> Bool {
        guard let values = game.actorValues.runtime, let holder = holder(of: key) else {
            return false
        }
        return values.hasZeroHealth(holder)
    }

    public func holder(of key: ReferenceKey) -> ActorValueHolder? {
        if key == .player {
            return .player
        }
        guard
            let streamer = game.streamer,
            let actor = streamer.referenceEntry(key: key)?.placedActor
        else { return nil }
        return ActorValueHolder(
            key: key, subject: .actor(base: actor.base), cell: streamer.cellLocation(of: key)
        )
    }

    public func ragdollPose(of key: ReferenceKey) -> RagdollActorPose? {
        if key == .player {
            return playerRagdollPose
        }
        guard
            let renderer = game.renderer,
            let streamer = game.streamer,
            let actor = streamer.referenceEntry(key: key)?.placedActor,
            let playback = game.actorPlayback(for: key),
            let animated = playback.clip.orderedWorldTransforms(at: renderer.animationTime)
        else { return nil }
        return RagdollActorPose(
            reference: actor.formID,
            cell: streamer.cellLocation(of: key) ?? .interior(actor.formID),
            scale: actor.scale,
            actorToWorld: MatrixMath.placement(
                position: actor.placement.position,
                rotation: actor.placement.rotation,
                scale: actor.scale
            ),
            skeletonMeshPath: playback.clip.skeletonMeshPath,
            skeleton: playback.clip.skeleton,
            animatedBoneMatrices: animated
        )
    }

    public func animatedPose(of key: ReferenceKey) -> [String: float4x4]? {
        if key == .player {
            return game.gameSession?.playerBody?.animation.animatedBonesByName
        }
        return game.animatedPose(for: key)
    }

    /// The player body is drawn apart from the cell's actors, so its pose comes from
    /// the graph's buffer and its placement from the body.
    private var playerRagdollPose: RagdollActorPose? {
        guard
            let body = game.gameSession?.playerBody,
            let skeletonPath = body.assembly.visual.skeletonPath
                .flatMap({ path in attempt { try VirtualFileSystem.meshPath(path) } }),
            let animated = body.animation.animatedBoneMatrices,
            let cell = game.streamer?.currentCellLocation
        else { return nil }
        return RagdollActorPose(
            reference: .playerReference,
            cell: cell,
            scale: 1,
            actorToWorld: body.transform,
            skeletonMeshPath: skeletonPath,
            skeleton: body.animation.skeleton,
            animatedBoneMatrices: animated
        )
    }

    /// Membership in `raisedEvents` after the raise is the graph's own answer.
    public func raisePlayerGraphEvent(_ name: String) -> Bool {
        guard let gameSession = game.gameSession else { return false }
        gameSession.locomotion.raise(name)
        return gameSession.locomotion.status.raisedEvents.contains(name)
    }

    /// The same static broadphase the player capsule queries.
    public var ragdollStepWorld: DynamicStepWorld {
        guard let streamer = game.streamer else { return DynamicStepWorld() }
        return DynamicStepWorld(
            staticCandidates: { [weak streamer] bounds in
                streamer?.collisionCandidates(overlapping: bounds) ?? []
            }
        )
    }

    public func unloadedActorHome(of key: ReferenceKey) -> CellSceneLocation? {
        guard
            let streamer = game.streamer, streamer.referenceEntry(key: key) == nil,
            let placement = streamer.pluginPlacement(of: key), placement.entry.placedActor != nil
        else { return nil }
        return placement.home
    }
}
