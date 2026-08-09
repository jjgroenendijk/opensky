// The vocabulary one combat behavior machine speaks (issue #424, roadmap item
// 16.7): where an actor is in a fight, what it was told about the world this
// step, and what it asks the world for.
//
// Split from the machine itself so the values a caller passes and reads are
// legible without the state transitions between them, and so the panel readout
// and the condition seam can name a phase without importing the decision layer.
//
// ## Why one phase enum rather than a stance and an attack timer
//
// The dev target had a four-phase attack clock and nothing else, because it had
// nothing else to be doing. A mind is either closing, waiting, guarding,
// swinging, reeling, running or looking, and those are mutually exclusive: an
// actor cannot be fleeing and winding up at once. Spelling them as one enum is
// what makes "which of these is it in" a single readable answer in the panel, in
// a test assertion and in `GetCombatState` — and what makes an illegal
// combination unrepresentable rather than merely unlikely.
//
// Documented in docs/engine/combat.md.

import simd

/// Where one actor is in a fight.
nonisolated enum CombatBehaviorPhase: String, Equatable, Sendable, CaseIterable {
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
    var isEngaged: Bool {
        self != .idle && self != .disengaged
    }

    /// Whether an attack is in flight, which a stagger takes away.
    var isAttacking: Bool {
        self == .windup || self == .contact || self == .recovery
    }
}

/// What one observer currently makes of its target, as the combat layer needs
/// it.
///
/// A projection of 16.6's `DetectionPairState` rather than the state itself:
/// the combat machine needs the level read as a state and the position to walk
/// to, and handing it the whole pair state would let it act on a raw detection
/// level the perception pass owns the meaning of.
nonisolated struct CombatAwareness: Equatable, Sendable {
    /// How aware the observer is.
    var state: DetectionState
    /// Where the target was when it was last perceived, or nil when nothing has
    /// been perceived or everything perceived has decayed away. This is what a
    /// searching actor walks to.
    var lastKnownPosition: SIMD3<Float>?

    /// Nothing perceived.
    static let unaware = CombatAwareness(state: .unaware, lastKnownPosition: nil)

    /// Perceived outright, at `position`.
    static func detected(at position: SIMD3<Float>) -> CombatAwareness {
        CombatAwareness(state: .detected, lastKnownPosition: position)
    }

    /// Whether the observer has the target right now.
    var isDetected: Bool {
        state == .detected
    }
}

/// Everything one machine is told about the world for one fixed step.
///
/// A flat value rather than a world handle, for the reason
/// `CombatActorObservation` is one: the machine cannot then reach past what it
/// was given, and a test hands it a literal.
nonisolated struct CombatBehaviorInputs: Equatable, Sendable {
    /// Where the acting actor is standing, world space.
    var actorPosition: SIMD3<Float>
    /// Where its target is standing, world space.
    var targetPosition: SIMD3<Float>
    /// What the actor currently makes of that target.
    var awareness: CombatAwareness
    /// The actor's own weapon reach, world units, already scaled.
    var reach: Float
    /// Current health over maximum, 0 through 1.
    var healthFraction: Float
    /// False once the target is dead, which ends the fight whatever else is
    /// true.
    var isTargetAlive: Bool
    /// True when a script called `StartCombat`, which engages the actor without
    /// waiting for it to perceive anything and keeps it engaged while it cannot.
    var isForced: Bool

    init(
        actorPosition: SIMD3<Float>,
        targetPosition: SIMD3<Float>,
        awareness: CombatAwareness = .unaware,
        reach: Float = 0,
        healthFraction: Float = 1,
        isTargetAlive: Bool = true,
        isForced: Bool = false
    ) {
        self.actorPosition = actorPosition
        self.targetPosition = targetPosition
        self.awareness = awareness
        self.reach = reach
        self.healthFraction = healthFraction
        self.isTargetAlive = isTargetAlive
        self.isForced = isForced
    }

    /// Ground-plane distance between the actor and its target.
    ///
    /// Planar rather than solid, because reach is compared against it and an
    /// actor standing on a table is not out of sword range for being two
    /// metres up.
    var distance: Float {
        let offset = targetPosition - actorPosition
        return simd_length(SIMD2(offset.x, offset.y))
    }
}

/// Where the machine wants the actor to be, handed to 16.4 movement.
///
/// Positions rather than directions, because `MoveToPointControl` takes a point
/// and paths to it: a direction would need a second authority to turn it into
/// somewhere the navmesh actually reaches.
nonisolated enum CombatMovementCommand: Equatable, Sendable {
    /// Close on the target.
    case approach(SIMD3<Float>)
    /// Go and look at the last place the target was perceived.
    case investigate(SIMD3<Float>)
    /// Get away from the target.
    case flee(SIMD3<Float>)
    /// Stop where you are.
    case hold

    /// The point this command paths to, or nil for `hold`.
    var destination: SIMD3<Float>? {
        switch self {
        case let .approach(point), let .investigate(point), let .flee(point): point
        case .hold: nil
        }
    }
}

/// What one advanced step of one machine did.
nonisolated struct CombatBehaviorStep: Equatable, Sendable {
    /// The phase after the step.
    var phase = CombatBehaviorPhase.idle
    /// True on the step the fight began, which is the step combat entry is
    /// recorded on.
    var startedFight = false
    /// True on the step an attack began, which is the step the attack clip is
    /// asked for.
    var startedAttack = false
    /// True on the contact step, which is the step the hit volume runs on.
    var reachedContact = false
    /// True on the step a guard went up.
    var raisedBlock = false
    /// True on the step a search began.
    var startedSearch = false
    /// True on the step pursuit ended, which is the step the 16.5 package is
    /// resumed on.
    var endedPursuit = false
    /// Where the actor should be heading, or nil when this step asked for no
    /// change in movement.
    var command: CombatMovementCommand?

    /// The step a machine that did nothing reports.
    static let idle = CombatBehaviorStep()
}
