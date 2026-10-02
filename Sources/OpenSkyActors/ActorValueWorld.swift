// The world side of the actor-value domain: what `ActorValueCoordinator` reads
// from the running session. The app answers it; a test passes a fake.
// See docs/engine/coordinators.md.

import OpenSkyFormatsESM
import OpenSkyGameData

/// What `ActorValueCoordinator` reads from the running world.
@MainActor
public protocol ActorValueWorld: AnyObject {
    /// The player and every resident actor. An actor in an unloaded cell is
    /// not simulated, so it does not regenerate.
    func regeneratingHolders() -> [ActorValueHolder]
    /// Nil when no actor is resident.
    func nearestActorValueHolder() -> ActorValueHolder?
    func isCasting(_ key: ReferenceKey) -> Bool
}
