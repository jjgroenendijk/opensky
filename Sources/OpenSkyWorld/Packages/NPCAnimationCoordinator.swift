// Plays the in-place gait clip that matches each NPC mover's drive. The mover
// owns the capsule; this only picks the clip. See docs/engine/coordinators.md.

import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics

/// What the NPC animation coordinator reads from the session.
@MainActor
public protocol NPCAnimationWorld: AnyObject {
    func actorPlayback(for actor: ReferenceKey) -> ActorAnimationPlayback?
    /// Nil without game data.
    var animationFiles: (any GameFileSource)? { get }
}

/// Caches each loaded gait clip, and each clip that failed to load, by
/// skeleton and animation path.
@MainActor
public final class NPCAnimationCoordinator {
    private var clips: [String: ActorAnimationClip] = [:]
    public private(set) var unresolvableClips: Set<String> = []

    weak var world: (any NPCAnimationWorld)?

    public init() {}

    public func attach(world: any NPCAnimationWorld) {
        self.world = world
    }

    public func drive(_ update: NPCLocomotionDriveUpdate) {
        guard let playback = world?.actorPlayback(for: update.actor) else { return }
        guard update.intent != .still else {
            playback.setLocomotionClip(nil)
            return
        }
        playback.setLocomotionClip(gaitClip(
            update.gait,
            skeletonMeshPath: playback.clip.skeletonMeshPath,
            female: playback.female
        ))
    }

    /// Nil for a gait with no direct clip, without game data, or when the clip
    /// does not load. A failed load is not retried.
    public func gaitClip(
        _ gait: LocomotionGait,
        skeletonMeshPath: String,
        female: Bool
    ) -> ActorAnimationClip? {
        guard
            let files = world?.animationFiles,
            let path = ActorAnimationClipLoader.gaitAnimationPath(gait, female: female)
        else { return nil }
        let cacheKey = "\(skeletonMeshPath)#\(path)"
        guard !unresolvableClips.contains(cacheKey) else { return nil }
        if let cached = clips[cacheKey] {
            return cached
        }
        guard
            let clip = try? ActorAnimationClipLoader.clip(
                skeletonMeshPath: skeletonMeshPath,
                animationPath: path,
                readHKX: { filePath in try HKXFile(data: files.contents(forPath: filePath)) }
            )
        else {
            unresolvableClips.insert(cacheKey)
            return nil
        }
        clips[cacheKey] = clip
        return clip
    }
}
