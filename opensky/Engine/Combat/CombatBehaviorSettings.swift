// Every number the combat mind runs on (issue #424, roadmap item 16.7), in one
// place and stated as OpenSky's own.
//
// ## Why these are not read from records
//
// `DevTargetDriver` — the clock this item deletes — carried the same statement
// for its four cadence constants, and it is still true for all fifteen here:
// no record in the load order states an attack cadence, a block probability, a
// flee threshold, a search duration or how often a caster prefers a spell to a
// sword. Vanilla's live in the combat-AI binary
// and in `GameSettings` this engine has no decoded consumer for, and inventing a
// citation for a number that was chosen would be worse than choosing it in the
// open. So every value below is OpenSky's, chosen for a reason written beside
// it, and `docs/engine/combat.md` repeats the list so a reader who never opens
// this file still sees which numbers are ours.
//
// A struct rather than static constants on the machine, for one reason: a test
// that wants a fight to resolve in a hundred fixed steps rather than in a
// thousand shortens the durations here instead of running for sixteen simulated
// seconds per assertion. The shipping values are `standard`.
//
// Documented in docs/engine/combat.md.

import Foundation

/// The cadence, spacing, block, flee and search numbers one combat behavior
/// machine runs on.
nonisolated struct CombatBehaviorSettings: Equatable, Sendable {
    /// Seconds an actor waits between the end of one attack and the start of
    /// the next.
    ///
    /// Inherited unchanged from the dev target's `intervalSeconds`, and for its
    /// reason: slow enough that a player can block, draw a bow, and watch what
    /// happened between blows.
    var attackIntervalSeconds: Float = 1.6

    /// Seconds from an attack starting to its contact step, which is roughly
    /// where the vanilla one-handed attack clip puts its `HitFrame`.
    var windupSeconds: Float = 0.45

    /// Seconds of follow-through after contact, during which no new attack
    /// starts.
    var recoverySeconds: Float = 0.35

    /// How long a stagger holds the attack away.
    var staggerSeconds: Float = 0.7

    /// The chance, 0 through 1, that an actor spends the gap before its next
    /// attack with its guard up rather than waiting.
    ///
    /// Rolled once per attack cycle from the actor's own seeded generator, so a
    /// fight is reproducible and two actors in the same room do not block in
    /// lockstep. Roughly one gap in three: often enough that a player learns to
    /// wait a guard out, rare enough that attacking is still the way a fight
    /// ends.
    var blockChance: Float = 0.35

    /// How long a raised guard is held.
    ///
    /// Deliberately equal to `attackIntervalSeconds`: blocking *replaces* the
    /// wait rather than being added to it, so an actor that blocks does not
    /// thereby attack sooner or later than one that did not. Two constants
    /// rather than one because the relationship is a choice, not an identity —
    /// a longer guard is a legitimate future tuning and would not silently
    /// change the attack cadence with it.
    var blockSeconds: Float = 1.6

    /// How far inside its own weapon reach an actor closes before it stops
    /// approaching, world units.
    ///
    /// A margin rather than zero because the mover's own waypoint tolerance is
    /// twelve units and a target standing exactly at the reach boundary would
    /// otherwise alternate between approaching and spacing every step.
    var reachSlack: Float = 24

    /// Seconds between one movement command and the next while an actor is
    /// approaching or fleeing.
    ///
    /// The mover paths once per command, so this is how often a chase notices
    /// that the player moved. An eighth of a second would path eight times a
    /// second per actor for a target that moved a few units; half a second at
    /// the eight-actor cap is sixteen path queries a second, which the 16.4
    /// budget already covers.
    var commandIntervalSeconds: Float = 0.5

    /// The health fraction, 0 through 1, at or below which an actor breaks off
    /// and runs.
    ///
    /// A fifth of its bar. High enough that a player sees the disengage happen
    /// rather than killing through it, low enough that an actor does not flee
    /// from the first blow it takes.
    var fleeHealthFraction: Float = 0.2

    /// How far from its current position a fleeing actor asks to be, world
    /// units. About twenty metres in Skyrim's scale.
    var fleeDistance: Float = 1400

    /// How far from the target a fleeing actor must get before it stops being
    /// in the fight at all, world units.
    ///
    /// Larger than `fleeDistance` would place it in one hop, so a flee that the
    /// navmesh cuts short is retried rather than ending the fight where it
    /// started.
    var fleeBreakDistance: Float = 1800

    /// The chance, 0 through 1, that an actor standing inside its own weapon
    /// reach casts rather than swings (issue #473).
    ///
    /// Only inside weapon reach: an actor that cannot reach its target with a
    /// weapon casts whenever it can afford to, because the alternative is
    /// walking toward somebody while holding a spell it could have thrown.
    /// Even odds in the one case where both are available — a caster that never
    /// swings is pinned in place by an opponent who closes on it, and one that
    /// always swings is a mage the player never sees cast.
    var castChance: Float = 0.5

    /// How long a maintained cast is held before the actor lets go, seconds.
    ///
    /// OpenSky's number and unavoidably so: a concentration spell has no
    /// duration of its own — UESP states the rule as "the duration is
    /// determined by how long you hold the casting trigger"
    /// (<https://en.uesp.net/wiki/Skyrim:Magic_Overview>) — so an NPC needs one
    /// stated somewhere. A second and a half is two applications of a
    /// once-a-second effect, which is long enough for a player to see a beam
    /// and short enough that the caster re-decides while the fight is still
    /// moving.
    var concentrationSeconds: Float = 1.5

    /// How long an actor that lost its target searches the last place it saw it
    /// before giving up.
    ///
    /// Eight seconds is long enough for a player to hear the search end and
    /// short enough that a hidden player is not pinned in place by it.
    var searchSeconds: Float = 8

    /// The shipping numbers.
    static let standard = CombatBehaviorSettings()

    /// Every duration divided by ten, for tests that assert on a whole fight
    /// without simulating half a minute of one.
    ///
    /// Probabilities and distances are untouched: shortening a duration changes
    /// how long a test runs, and changing a probability would change what it
    /// tests.
    static let quick = CombatBehaviorSettings(
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
