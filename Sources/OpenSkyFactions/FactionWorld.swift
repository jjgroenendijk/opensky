// The world side of the faction domain: what `FactionCoordinator` reads from
// the running session. The app answers it; a test passes a fake.
// See docs/engine/coordinators.md.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// What `FactionCoordinator` reads from the running world.
@MainActor
public protocol FactionWorld: AnyObject {
    /// Nil when `key` is not the player and not a resident actor.
    func actorValueHolder(for key: ReferenceKey) -> ActorValueHolder?
    /// Every resident actor other than the player.
    func residentActorKeys() -> [ReferenceKey]
    /// The `NPC_` record a resident actor was placed from.
    func placedActorBase(of key: ReferenceKey) -> FormID?
    func cellLocation(of key: ReferenceKey) -> CellSceneLocation?
}
