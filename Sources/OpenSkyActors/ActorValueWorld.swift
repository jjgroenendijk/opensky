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
    /// The player is in combat while any actor fights it.
    func isInCombat(_ key: ReferenceKey) -> Bool
    /// The player's worn weight while it sprints, or nil while it does not.
    func playerSprintLoad() -> Float?
    /// An empty stamina bar turns the player's sprint into a run.
    func setPlayerSprintAllowed(_ allowed: Bool)
    /// The horse the player rides, or nil. Its own stamina pays for its sprint.
    func riddenHorse() -> ActorValueHolder?
    /// True while the ridden horse sprints and moves.
    func isRiddenHorseSprinting() -> Bool
    /// An empty stamina bar turns the horse's sprint into a run.
    func setRiddenHorseSprintAllowed(_ allowed: Bool)
    /// What the player carries, with worn armour at its perk weight. Nil without items.
    func playerCarriedWeight() -> Float?
    /// An over-encumbered player can only walk; true shows `sOverEncumbered` on the HUD.
    func setPlayerOverencumbered(_ overencumbered: Bool)
}

extension ActorValueWorld {
    /// A session with no locomotion never sprints.
    public func playerSprintLoad() -> Float? {
        nil
    }

    public func setPlayerSprintAllowed(_: Bool) {}

    /// A session with no mounts has no horse.
    public func riddenHorse() -> ActorValueHolder? {
        nil
    }

    public func isRiddenHorseSprinting() -> Bool {
        false
    }

    public func setRiddenHorseSprintAllowed(_: Bool) {}

    public func playerCarriedWeight() -> Float? {
        nil
    }

    public func setPlayerOverencumbered(_: Bool) {}
}
