// What a procedure asks the world to do besides walking, and what the world
// answers. See docs/engine/package-schedules.md, "Procedure machines".

import OpenSkyFormatsESM
import OpenSkyPhysics
import simd

/// One act of a procedure. The world answers each with a `PackageActionResult`.
nonisolated public enum PackageAction: Equatable, Sendable {
    /// LockDoors and UnlockDoors: the doors the actor owns in the place. No walk.
    case setDoorsLocked(Bool, center: SIMD3<Float>, radius: Float)
    /// Find: the references in the place that match the selector.
    case find(Package.Target, center: SIMD3<Float>, radius: Float)
    case activate(ReferenceKey)
    /// Acquire: the actor picks the item up.
    case pickUp(ReferenceKey)
    /// Say: one line of the topic, spoken to the target.
    case say(topic: FormID?, to: ReferenceKey?)
    /// ForceGreet: the actor starts a conversation with the player.
    case forceGreet(topic: FormID?)
    /// DialogueActivate: the actor starts a conversation with the target.
    case talk(to: ReferenceKey)
    /// UseWeapon: attack the target. OpenSky has no scripted attack outside a fight, so
    /// only a procedure that may start combat can attack.
    case attack(ReferenceKey?, startsCombat: Bool)
    /// UseMagic: a cast of the selected spell at the target.
    case cast(Package.Target?, at: ReferenceKey?)
    /// Shout: the selected shout at the target.
    case shout(Package.Target?, at: ReferenceKey?)
    /// Guard: draw the weapon and say a trespass line to the intruder. `level` counts
    /// the warnings, the first one 1.
    case warn(ReferenceKey, level: Int)
    /// Guard: the intruder left, so put the weapon away.
    case standDown
}

nonisolated public enum PackageActionResult: Equatable, Sendable {
    case done
    /// The world cannot do it, or it went wrong; the procedure fails.
    case failed
    /// It takes this many real seconds, such as a spoken line.
    case lasts(seconds: Float)
    /// What a find found, nearest first.
    case found([ReferenceKey])
}

/// Where the actor and the reference its procedure watches stand this tick.
nonisolated public struct PackageSenses: Equatable, Sendable {
    public let actor: SIMD3<Float>
    public let watched: SIMD3<Float>?
    /// How the watched reference moves, so a follower can sprint or sneak with it.
    public let watchedGait: LocomotionGait?

    public init(
        actor: SIMD3<Float>, watched: SIMD3<Float>?, watchedGait: LocomotionGait? = nil
    ) {
        self.actor = actor
        self.watched = watched
        self.watchedGait = watchedGait
    }
}
