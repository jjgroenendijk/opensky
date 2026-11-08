import OpenSkyFormatsESM
import OpenSkyMagicInterface
import OpenSkyPerceptionInterface
import simd

/// Where one actor is in a fight.
nonisolated public enum CombatBehaviorPhase: String, Equatable, Sendable, CaseIterable {
    /// Not fighting. Hostile perhaps, but nothing perceived, so nothing to do.
    case idle
    /// Closing on the target through 16.4 movement.
    case approaching
    /// Inside weapon reach, waiting out the interval before the next attack.
    case spacing
    /// Inside weapon reach with its guard up, which is what makes the player's
    /// hit resolve through the block half of the 15.4 damage formula.
    case blocking
    /// Winding up. The attack clip is playing and nothing has connected.
    case windup
    /// Casting: a spell is charging or being held. Its own phase, because a cast is
    /// timed by the SPIT charge time, and an actor cannot swing and cast at once.
    case casting
    /// The contact step. Exactly one step long, which is what makes a hit land
    /// once rather than once per frame of the swing.
    case contact
    /// Following through. No new attack starts until this ends.
    case recovery
    /// Interrupted by a hit, exactly as the graph's own stagger transition takes
    /// the player's attack away.
    case staggered
    /// Broken off at low health and running along a navmesh path away from the
    /// target. Still in the fight, which is why combat music keeps playing.
    case fleeing
    /// The target was lost. Moving to the last place it was perceived and
    /// looking around. `GetCombatState` reads 2 here.
    case searching
    /// Pursuit is over. The actor has been handed back to its 16.5 package and
    /// is out of combat until it perceives the target again.
    case disengaged

    /// Whether this phase counts as being in the fight, which is what the
    /// player's combat state and the combat music derive from.
    ///
    /// Searching counts and disengaged does not: an actor hunting for a player
    /// who broke line of sight is still fighting, and one that gave up and went
    /// back to its schedule is not.
    public var isEngaged: Bool {
        self != .idle && self != .disengaged
    }

    /// Whether an attack is in flight, which a stagger takes away.
    ///
    /// A cast counts: a blow that interrupts a swing interrupts a charge too,
    /// and the runtime drops the charging spell when it staggers the actor.
    public var isAttacking: Bool {
        self == .windup || self == .contact || self == .recovery || self == .casting
    }
}
