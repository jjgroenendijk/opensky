// Plays the in-place gait clip that matches each NPC mover's drive. The mover
// owns the capsule; this only picks the clip. See docs/engine/coordinators.md.

public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyPhysics
public import OpenSkyWorldInterface

/// What the NPC animation coordinator reads from the session.
@MainActor
public protocol NPCAnimationWorld: AnyObject {
    /// Nil without game data.
    var animationClips: ActorClipLoader? { get }
}

/// Picks each mover's gait clip. Clips load off the main actor; until one arrives,
/// the actor keeps the clip it plays.
@MainActor
public final class NPCAnimationCoordinator {
    /// Each actor's animation playback; the composition root answers it from the streamer.
    public var actorPlayback: (ReferenceKey) -> ActorAnimationPlayback? = { _ in nil }
    /// Skeleton and path of each gait clip that failed to load, as `skeleton#path`.
    private(set) var unresolvableClips: Set<String> = []
    /// Movers whose gait clip is still loading.
    private var waiting: [ReferenceKey: ActorClipKey] = [:]
    /// Each horse's rider, which plays the rider clip of the horse's gait.
    public private(set) var riders: [ReferenceKey: ReferenceKey] = [:]
    /// Each rider's gait, nil for standing, and the body its rider clip was set on. A
    /// body that loads later or is rebuilt starts on its own idle, so it gets the clip again.
    private var riderGaits: [ReferenceKey: LocomotionGait?] = [:]
    private var riderBodies: [ReferenceKey: ObjectIdentifier] = [:]

    weak let world: (any NPCAnimationWorld)?

    public init(world: any NPCAnimationWorld) {
        self.world = world
    }

    public func drive(_ update: NPCLocomotionDriveUpdate) {
        if let rider = riders[update.actor] {
            playRiderClip(rider, gait: update.intent == .still ? nil : update.gait)
        }
        guard let playback = actorPlayback(update.actor) else { return }
        waiting[update.actor] = nil
        // The actor's own graph plays its gait.
        guard !playback.isGraphDriven else { return }
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

    /// Seats `rider` on `horse` for animation: it plays the rider idle now, and the rider
    /// clip of the horse's gait as the horse moves.
    public func ride(_ rider: ReferenceKey, on horse: ReferenceKey) {
        riders[horse] = rider
        playRiderClip(rider, gait: nil)
    }

    private func playRiderClip(_ rider: ReferenceKey, gait: LocomotionGait?) {
        riderGaits[rider] = gait
        guard let playback = actorPlayback(rider) else {
            riderBodies[rider] = nil
            return
        }
        riderBodies[rider] = ObjectIdentifier(playback)
        waiting[rider] = nil
        let key = ActorClipKey(
            skeletonMeshPath: playback.clip.skeletonMeshPath,
            animationPath: ActorAnimationClipLoader.riderAnimationPath(gait)
        )
        apply(key, to: rider, playback: playback)
    }

    /// Hands a rider that got off back to its own clips.
    public func dismount(_ rider: ReferenceKey) {
        riders = riders.filter { $0.value != rider }
        riderGaits[rider] = nil
        riderBodies[rider] = nil
        waiting[rider] = nil
        actorPlayback(rider)?.setLocomotionClip(nil)
    }

    /// Sets the clip of each mover whose clip arrived, and of each rider whose body is
    /// new. Runs each frame after the loader drains.
    public func applyArrivedClips() {
        for rider in riders.values.sorted() {
            guard
                let playback = actorPlayback(rider),
                riderBodies[rider] != ObjectIdentifier(playback)
            else { continue }
            playRiderClip(rider, gait: riderGaits[rider].flatMap(\.self))
        }
        for actor in waiting.keys.sorted() {
            guard let key = waiting[actor] else { continue }
            waiting[actor] = nil
            guard let playback = actorPlayback(actor) else { continue }
            apply(key, to: actor, playback: playback)
        }
    }

    /// The clip when it is loaded. Nil for a gait with no direct clip, without game
    /// data, while it loads, or when it failed. A failed load is not retried.
    func gaitClip(
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
        let paths = ActorAnimationClipLoader.gaitAnimationPaths(
            gait, skeletonMeshPath: skeletonMeshPath, female: female
        )
        guard !paths.isEmpty else { return nil }
        return ActorClipKey(skeletonMeshPath: skeletonMeshPath, animationPaths: paths)
    }

    private func state(of key: ActorClipKey) -> AssetLoadState<ActorAnimationClip>? {
        guard let clips = world?.animationClips else { return nil }
        let state = clips.state(of: key)
        if case .failed = state {
            unresolvableClips.insert(
                "\(key.skeletonMeshPath)#\(key.animationPaths.joined(separator: "|"))"
            )
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
