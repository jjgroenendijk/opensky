// The vocabulary of a combat behavior machine: the actor's phase in a fight,
// what it was told this step, and what it asks for. One phase enum, because the
// states exclude each other, so an illegal mix cannot be written.
// See docs/engine/combat-behavior.md.

import OpenSkyFormatsESM
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

/// What one observer makes of its target, as the combat layer needs it: a
/// projection of `DetectionPairState`, not the raw detection level.
nonisolated public struct CombatAwareness: Equatable, Sendable {
    /// How aware the observer is.
    public var state: DetectionState
    /// Where the target was when it was last perceived, or nil when nothing has
    /// been perceived or everything perceived has decayed away. This is what a
    /// searching actor walks to.
    public var lastKnownPosition: SIMD3<Float>?

    /// Nothing perceived.
    public static let unaware = CombatAwareness(state: .unaware, lastKnownPosition: nil)

    /// Perceived outright, at `position`.
    public static func detected(at position: SIMD3<Float>) -> CombatAwareness {
        CombatAwareness(state: .detected, lastKnownPosition: position)
    }

    /// Whether the observer has the target right now.
    public var isDetected: Bool {
        state == .detected
    }

    public init(state: DetectionState, lastKnownPosition: SIMD3<Float>? = nil) {
        self.state = state
        self.lastKnownPosition = lastKnownPosition
    }
}

/// One spell an actor could cast this step. Resolved by the session, so the
/// decision layer and the cast loop agree on cost.
nonisolated public struct CombatSpellOption: Equatable, Sendable {
    /// The SPEL this option casts.
    public let spell: ReferenceKey
    /// Magicka one cast takes, from `ResolvedSpell.cost`.
    public let cost: Float
    /// How far it reaches, world units, already resolved: SPIT's range, or the
    /// session's own aimed ceiling for a record that bounds nothing.
    public let range: Float
    /// SPIT's charge time, which is how long the actor holds the cast before it
    /// leaves the hand.
    public let chargeSeconds: Float
    /// True for a concentration spell, which is maintained rather than
    /// released the instant it finishes charging.
    public let isConcentration: Bool

    public init(
        spell: ReferenceKey,
        cost: Float,
        range: Float,
        chargeSeconds: Float = 0,
        isConcentration: Bool = false
    ) {
        self.spell = spell
        self.cost = cost
        self.range = range
        self.chargeSeconds = chargeSeconds
        self.isConcentration = isConcentration
    }
}

/// What one actor can pay for and what it could cast.
nonisolated public struct CombatCastingProfile: Equatable, Sendable {
    /// Magicka available right now, which is what affordability is checked
    /// against.
    public var magicka: Float = 0
    /// The hostile spells the actor knows that this build can actually deliver,
    /// in ascending spell order.
    public var options: [CombatSpellOption] = []

    /// An actor that knows nothing castable — every actor before 19.10, and
    /// every warrior after it.
    public static let none = CombatCastingProfile()

    public init(magicka: Float = 0, options: [CombatSpellOption] = []) {
        self.magicka = magicka
        self.options = options
    }
}

/// Everything one machine is told about the world for one fixed step.
///
/// A flat value rather than a world handle, for the reason
/// `CombatActorObservation` is one: the machine cannot then reach past what it
/// was given, and a test hands it a literal.
nonisolated public struct CombatBehaviorInputs: Equatable, Sendable {
    /// Where the acting actor is standing, world space.
    public var actorPosition: SIMD3<Float>
    /// Where its target is standing, world space.
    public var targetPosition: SIMD3<Float>
    /// What the actor currently makes of that target.
    public var awareness: CombatAwareness
    /// The actor's own weapon reach, world units, already scaled.
    public var reach: Float
    /// Current health over maximum, 0 through 1.
    public var healthFraction: Float
    /// False once the target is dead, which ends the fight whatever else is
    /// true.
    public var isTargetAlive: Bool
    /// True when a script called `StartCombat`, which engages the actor without
    /// waiting for it to perceive anything and keeps it engaged while it cannot.
    public var isForced: Bool
    /// What the actor could cast and what it can pay for.
    public var casting: CombatCastingProfile

    public init(
        actorPosition: SIMD3<Float>,
        targetPosition: SIMD3<Float>,
        awareness: CombatAwareness = .unaware,
        reach: Float = 0,
        healthFraction: Float = 1,
        isTargetAlive: Bool = true,
        isForced: Bool = false,
        casting: CombatCastingProfile = .none
    ) {
        self.actorPosition = actorPosition
        self.targetPosition = targetPosition
        self.awareness = awareness
        self.reach = reach
        self.healthFraction = healthFraction
        self.isTargetAlive = isTargetAlive
        self.isForced = isForced
        self.casting = casting
    }

    /// Ground-plane distance between the actor and its target.
    ///
    /// Planar rather than solid, because reach is compared against it and an
    /// actor standing on a table is not out of sword range for being two
    /// metres up.
    public var distance: Float {
        let offset = targetPosition - actorPosition
        return simd_length(SIMD2(offset.x, offset.y))
    }
}

/// Where the machine wants the actor to be, handed to 16.4 movement.
///
/// Positions rather than directions, because the NPC mover takes a point
/// and paths to it: a direction would need a second authority to turn it into
/// somewhere the navmesh actually reaches.
nonisolated public enum CombatMovementCommand: Equatable, Sendable {
    /// Close on the target.
    case approach(SIMD3<Float>)
    /// Go and look at the last place the target was perceived.
    case investigate(SIMD3<Float>)
    /// Get away from the target.
    case flee(SIMD3<Float>)
    /// Stop where you are.
    case hold

    /// The point this command paths to, or nil for `hold`.
    public var destination: SIMD3<Float>? {
        switch self {
        case let .approach(point), let .investigate(point), let .flee(point): point
        case .hold: nil
        }
    }
}

/// What one advanced step of one machine did.
nonisolated public struct CombatBehaviorStep: Equatable, Sendable {
    /// The phase after the step.
    public var phase = CombatBehaviorPhase.idle
    /// True on the step the fight began, which is the step combat entry is
    /// recorded on.
    public var startedFight = false
    /// True on the step an attack began, which is the step the attack clip is
    /// asked for.
    public var startedAttack = false
    /// True on the contact step, which is the step the hit volume runs on.
    public var reachedContact = false
    /// True on the step a guard went up.
    public var raisedBlock = false
    /// True on the step a search began.
    public var startedSearch = false
    /// The spell whose cast began this step, or nil when none did. Carries the
    /// option rather than a flag so the runtime casts what the machine chose
    /// rather than re-choosing for itself.
    public var startedCast: CombatSpellOption?
    /// The spell whose cast the machine let go of this step, which is the step
    /// the magicka is spent and the delivery happens on.
    public var releasedCast: CombatSpellOption?
    /// True on the step a cast in flight was dropped without being released —
    /// the actor broke off, lost its target or gave up mid-charge.
    public var cancelledCast = false
    /// True on the step pursuit ended, which is the step the 16.5 package is
    /// resumed on.
    public var endedPursuit = false
    /// Where the actor should be heading, or nil when this step asked for no
    /// change in movement.
    public var command: CombatMovementCommand?
}
