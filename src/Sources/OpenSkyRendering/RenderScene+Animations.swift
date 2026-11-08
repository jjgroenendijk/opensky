// Poses the scene's actors once a frame from one shared world clock, with the ragdoll
// and severed-head overrides on top (docs/engine/actor-graphs.md).

import OpenSkyFormatsCore
import OpenSkyRenderCore

nonisolated extension RenderScene {
    /// Samples every resident actor at one shared world clock. A malformed
    /// runtime sample freezes only that actor; validated clips normally update.
    @discardableResult
    public func updateAnimations(at time: Float) -> Int {
        var poses: [ObjectIdentifier: SkeletonPose] = [:]
        var failedClips = Set<ObjectIdentifier>()
        var updatedMeshes = Set<ObjectIdentifier>()
        var updated = 0
        for animation in animations {
            guard let actor = animation as? any SharedPoseAnimation else {
                updated += animation.update(at: time)
                continue
            }
            actor.advanceClock(to: time)
            let key = actor.sharedClipKey
            if failedClips.contains(key) {
                continue
            }
            let pose: SkeletonPose
            if let cached = poses[key] {
                pose = cached
            } else if let sampled = actor.sampleSharedPose(at: time) {
                poses[key] = sampled
                pose = sampled
            } else {
                failedClips.insert(key)
                continue
            }
            let overrides = actor.posesSeveredHead ? severedHeadPoses : ragdollPoses
            let posed = overrides[actor.actorFormID].map {
                pose.overriding($0, parents: actor.poseParents)
            } ?? pose
            updated += actor.apply(posed, updating: &updatedMeshes)
        }
        return updated
    }

    /// Restores all resident actor meshes to their NIF bind palettes.
    @discardableResult
    public func resetAnimationsToBindPose() -> Int {
        animations.reduce(0) { $0 + $1.resetToBindPose() }
    }
}
