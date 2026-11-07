// Finds the animation objects that draw one placed actor.

public import OpenSkyFormatsESM
public import OpenSkyRendering

nonisolated extension RenderScene {
    /// Nil for a static actor the animation layer found no rig for.
    public func actorPlayback(for actor: FormID) -> ActorAnimationPlayback? {
        animations.lazy
            .compactMap { $0 as? ActorAnimationPlayback }
            .first { $0.actor == actor && !$0.posesSeveredHead }
    }

    /// The playback of `actor`'s cut head, or nil while the head is on.
    public func severedHeadPlayback(for actor: FormID) -> ActorAnimationPlayback? {
        animations.lazy
            .compactMap { $0 as? ActorAnimationPlayback }
            .first { $0.actor == actor && $0.posesSeveredHead }
    }

    public func faceMorphPlayback(for actor: FormID) -> FaceMorphPlayback? {
        animations.lazy
            .compactMap { $0 as? FaceMorphPlayback }
            .first { $0.actor == actor }
    }
}
