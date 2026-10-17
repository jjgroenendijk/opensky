// What the magic coordinator asks the app to do. See docs/engine/coordinators.md.

import OpenSkyFormatsESM

/// One change to the world outside the magic domain, raised by a magic effect.
nonisolated public enum MagicCommand: Equatable, Sendable {
    /// A Stagger effect began on the actor, with its magnitude.
    case stagger(ReferenceKey, magnitude: Float)
    /// A Spawn Hazard effect began: the hazard is placed at the actor.
    case spawnHazard(ReferenceKey, at: ReferenceKey)
}
