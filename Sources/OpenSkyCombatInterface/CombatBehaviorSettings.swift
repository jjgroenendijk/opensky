// Every number the combat mind runs on. No record states an attack cadence, block
// chance, flee threshold or search time, so each value is ours, with its reason
// beside it. A struct, so a test can shorten the durations instead of simulating
// many seconds. The shipping values are `standard`. See docs/engine/combat-behavior.md.

import Foundation

/// The cadence, spacing, block, flee and search numbers one combat behavior
/// machine runs on.
nonisolated public struct CombatBehaviorSettings: Equatable, Sendable {
    /// Seconds an actor waits between the end of one attack and the start of
    /// the next.
    ///
    /// Inherited unchanged from the dev target's `intervalSeconds`, and for its
    /// reason: slow enough that a player can block, draw a bow, and watch what
    /// happened between blows.
    public var attackIntervalSeconds: Float = 1.6

    /// Seconds from an attack starting to its contact step, which is roughly
    /// where the vanilla one-handed attack clip puts its `HitFrame`.
    public var windupSeconds: Float = 0.45

    /// Seconds of follow-through after contact, during which no new attack
    /// starts.
    public var recoverySeconds: Float = 0.35

    /// How long a stagger holds the attack away.
    public var staggerSeconds: Float = 0.7

    /// The chance, 0 through 1, that an actor guards in the gap before its next
    /// attack. Rolled per cycle from the actor's seeded generator, so fights repeat
    /// and two actors do not block in step. About one gap in three.
    public var blockChance: Float = 0.35

    /// How long a raised guard is held. Equal to `attackIntervalSeconds`, so a block
    /// replaces the wait and does not change the attack cadence. Kept separate so
    /// either can be tuned alone.
    public var blockSeconds: Float = 1.6

    /// How far inside its own weapon reach an actor closes before it stops
    /// approaching, world units.
    ///
    /// A margin rather than zero because the mover's own waypoint tolerance is
    /// twelve units and a target standing exactly at the reach boundary would
    /// otherwise alternate between approaching and spacing every step.
    public var reachSlack: Float = 24

    /// Seconds between movement commands while approaching or fleeing. Each command
    /// paths once; half a second at the eight-actor cap is sixteen queries a second.
    public var commandIntervalSeconds: Float = 0.5

    /// The health fraction, 0 through 1, at or below which an actor breaks off
    /// and runs.
    ///
    /// A fifth of its bar. High enough that a player sees the disengage happen
    /// rather than killing through it, low enough that an actor does not flee
    /// from the first blow it takes.
    public var fleeHealthFraction: Float = 0.2

    /// How far from its current position a fleeing actor asks to be, world
    /// units. About twenty metres in Skyrim's scale.
    public var fleeDistance: Float = 1400

    /// How far from the target a fleeing actor must get before it stops being
    /// in the fight at all, world units.
    ///
    /// Larger than `fleeDistance` would place it in one hop, so a flee that the
    /// navmesh cuts short is retried rather than ending the fight where it
    /// started.
    public var fleeBreakDistance: Float = 1800

    /// The chance, 0 through 1, that an actor within weapon reach casts rather than
    /// swings. Out of reach it always casts when it can pay. Even odds, so a caster
    /// neither freezes when closed on nor never casts.
    public var castChance: Float = 0.5

    /// How long an NPC holds a concentration cast, in seconds. Ours: the player's
    /// trigger sets the duration (<https://en.uesp.net/wiki/Skyrim:Magic_Overview>).
    /// 1.5 s shows the beam and lets the caster re-decide soon.
    public var concentrationSeconds: Float = 1.5

    /// How long an actor that lost its target searches the last place it saw it
    /// before giving up.
    ///
    /// Eight seconds is long enough for a player to hear the search end and
    /// short enough that a hidden player is not pinned in place by it.
    public var searchSeconds: Float = 8

    /// The shipping numbers.
    public static let standard = CombatBehaviorSettings()

    /// Every duration divided by ten, for tests that assert on a whole fight
    /// without simulating half a minute of one.
    ///
    /// Probabilities and distances are untouched: shortening a duration changes
    /// how long a test runs, and changing a probability would change what it
    /// tests.
    public static let quick = CombatBehaviorSettings(
        attackIntervalSeconds: 0.16,
        windupSeconds: 0.045,
        recoverySeconds: 0.035,
        staggerSeconds: 0.07,
        blockSeconds: 0.16,
        commandIntervalSeconds: 0.05,
        concentrationSeconds: 0.15,
        searchSeconds: 0.8
    )
}
