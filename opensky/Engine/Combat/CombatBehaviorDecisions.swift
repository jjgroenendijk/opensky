// The questions one combat step's inputs answer on their own (issues #424 and
// #473, roadmap items 16.7 and 19.10), plus the per-actor seed the machine's
// one random draw runs from.
//
// Split out of `CombatBehaviorMachine` because everything here is a pure
// function of the inputs and the settings rather than of the machine's state:
// how close the actor wants to be before it swings, whether it is hurt enough
// to run, which spell it could cast from where it is standing, and where it
// would run to at a given angle. Keeping them beside the phase transitions made
// the machine's own body the largest thing in the subsystem for no benefit —
// none of these reads a phase, a timer or a count.
//
// The one deliberate seam: `fleePoint` takes the turn angle rather than drawing
// it. The draw is the machine's, because the generator is the machine's and a
// fight has to replay exactly; the geometry is not.
//
// Documented in docs/engine/combat.md.

import Foundation
import simd

nonisolated extension CombatBehaviorInputs {
    /// How close the actor wants to be before it swings: its own reach, less
    /// the stated margin, and never negative.
    func strikingDistance(settings: CombatBehaviorSettings) -> Float {
        max(0, reach - settings.reachSlack)
    }

    /// Whether the actor is hurt enough to break off.
    func shouldFlee(settings: CombatBehaviorSettings) -> Bool {
        healthFraction.isFinite && healthFraction <= settings.fleeHealthFraction
    }

    /// Which spell this actor would cast if it cast now: the most expensive one
    /// it can both afford and reach with, ties broken by spell order
    /// (issue #473).
    ///
    /// Cost as the ordering is a stand-in for strength and is documented as
    /// one: no record states how a caster ranks its own spells, and taking the
    /// costliest affordable option spends a full magicka bar on the strongest
    /// thing it buys, then falls back down the list as the bar drains. Nil when
    /// nothing is affordable, in range, or known at all — which is every actor
    /// that fights with its hands.
    var castableSpell: CombatSpellOption? {
        casting.options
            .filter { $0.cost <= casting.magicka && distance <= $0.range }
            .sorted { ($0.cost, $1.spell) > ($1.cost, $0.spell) }
            .first
    }

    /// A point `fleeDistance` away, along the line from the target through the
    /// actor and turned by `turn` radians.
    ///
    /// Turned rather than straight because a straight line runs into whatever
    /// is behind the actor and the mover would give up against it; a different
    /// angle per draw means the retry after a failed path is a different
    /// request. Two actors fleeing the same swing scatter, which is also what a
    /// player expects to see.
    func fleePoint(turnedBy turn: Float, settings: CombatBehaviorSettings) -> SIMD3<Float> {
        let offset = actorPosition - targetPosition
        let planar = SIMD2(offset.x, offset.y)
        let base = simd_length(planar) > 0 ? simd_normalize(planar) : SIMD2<Float>(1, 0)
        let direction = SIMD2(
            base.x * cos(turn) - base.y * sin(turn),
            base.x * sin(turn) + base.y * cos(turn)
        )
        return actorPosition + SIMD3(direction.x, direction.y, 0) * settings.fleeDistance
    }
}

nonisolated extension CombatBehaviorMachine {
    /// A stable per-actor seed.
    ///
    /// Folded from the key's own spelling rather than from `hashValue`, because
    /// Swift seeds `String` hashing per process: a `hashValue` seed would make
    /// two runs of the same fight differ, which is exactly what the determinism
    /// tests exist to catch.
    static func seed(for key: ReferenceKey) -> UInt64 {
        var state = ConditionRandom.defaultSeed
        for byte in key.description.utf8 {
            state = (state ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return state
    }
}
