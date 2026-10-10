// Plays the in-place gait clip that matches each NPC mover's drive. The mover
// owns the capsule; this only picks the clip. See docs/engine/coordinators.md.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics

/// What the NPC animation coordinator reads from the session.
@MainActor
public protocol NPCAnimationWorld: AnyObject {
    func actorPlayback(for actor: ReferenceKey) -> ActorAnimationPlayback?
    /// Nil without game data.
    var animationClips: ActorClipLoader? { get }
}

/// Picks each mover's gait clip. Clips load off the main actor; until one arrives,
/// the actor keeps the clip it plays.
@MainActor
public final class NPCAnimationCoordinator {
    /// Skeleton and path of each gait clip that failed to load, as `skeleton#path`.
    public private(set) var unresolvableClips: Set<String> = []
    /// Movers whose gait clip is still loading.
    private var waiting: [ReferenceKey: ActorClipKey] = [:]

    weak var world: (any NPCAnimationWorld)?

    public init() {}

    public func attach(world: any NPCAnimationWorld) {
        self.world = world
    }

    public func drive(_ update: NPCLocomotionDriveUpdate) {
        guard let playback = world?.actorPlayback(for: update.actor) else { return }
        waiting[update.actor] = nil
        guard
            update.intent != .still,
            let key = gaitKey(
                update.gait, skeletonMeshPath: playback.clip.skeletonMeshPath,
                female: playback.female
            )
        else {
            playback.setLocomotionClip(nil)
            return
        }
        apply(key, to: update.actor, playback: playback)
    }

    /// Sets the clip of each mover whose clip arrived. Runs after the loader drains.
    public func applyArrivedClips() {
        for actor in waiting.keys.sorted() {
            guard let key = waiting[actor] else { continue }
            waiting[actor] = nil
            guard let playback = world?.actorPlayback(for: actor) else { continue }
            apply(key, to: actor, playback: playback)
        }
    }

    /// The clip when it is loaded. Nil for a gait with no direct clip, without game
    /// data, while it loads, or when it failed. A failed load is not retried.
    public func gaitClip(
        _ gait: LocomotionGait,
        skeletonMeshPath: String,
        female: Bool
    ) -> ActorAnimationClip? {
        guard let key = gaitKey(gait, skeletonMeshPath: skeletonMeshPath, female: female)
        else { return nil }
        return state(of: key)?.value
    }

    private func gaitKey(
        _ gait: LocomotionGait,
        skeletonMeshPath: String,
        female: Bool
    ) -> ActorClipKey? {
        ActorAnimationClipLoader.gaitAnimationPath(
            gait, skeletonMeshPath: skeletonMeshPath, female: female
        ).map {
            ActorClipKey(skeletonMeshPath: skeletonMeshPath, animationPath: $0)
        }
    }

    private func state(of key: ActorClipKey) -> AssetLoadState<ActorAnimationClip>? {
        guard let clips = world?.animationClips else { return nil }
        let state = clips.state(of: key)
        if case .failed = state {
            unresolvableClips.insert("\(key.skeletonMeshPath)#\(key.animationPath)")
        }
        return state
    }

    private func apply(
        _ key: ActorClipKey,
        to actor: ReferenceKey,
        playback: ActorAnimationPlayback
    ) {
        switch state(of: key) {
        case let .ready(clip): playback.setLocomotionClip(clip)
        case .loading: waiting[actor] = key
        case .failed, nil: playback.setLocomotionClip(nil)
        }
    }
}
