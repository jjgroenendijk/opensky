// Finds the animation objects that draw one placed actor.

import OpenSkyFormatsESM
import OpenSkyRendering

nonisolated extension RenderScene {
    /// Nil for a static actor the animation layer found no rig for.
    public func actorPlayback(for actor: FormID) -> ActorAnimationPlayback? {
        animations.lazy
            .compactMap { $0 as? ActorAnimationPlayback }
            .first { $0.actor == actor }
    }

    public func faceMorphPlayback(for actor: FormID) -> FaceMorphPlayback? {
        animations.lazy
            .compactMap { $0 as? FaceMorphPlayback }
            .first { $0.actor == actor }
    }
}
