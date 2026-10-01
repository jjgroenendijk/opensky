// Pure combat-step questions: approach distance, flee check, which spell is castable,
// and the flee point. Split from `CombatBehaviorMachine`, because none reads its state.
// `fleePoint` takes the turn angle; the machine owns the random draw, so fights replay.
// See docs/engine/combat-behavior.md.

import Foundation
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import simd

nonisolated extension CombatBehaviorInputs {
    /// How close the actor wants to be before it swings: its own reach, less
    /// the stated margin, and never negative.
    public func strikingDistance(settings: CombatBehaviorSettings) -> Float {
        max(0, reach - settings.reachSlack)
    }

    /// Whether the actor is hurt enough to break off.
    public func shouldFlee(settings: CombatBehaviorSettings) -> Bool {
        healthFraction.isFinite && healthFraction <= settings.fleeHealthFraction
    }

    /// The spell this actor would cast now: the costliest it can afford and reach, ties
    /// by spell order. Cost stands in for strength, because no record ranks spells.
    /// Nil when nothing qualifies.
    public var castableSpell: CombatSpellOption? {
        casting.options
            .filter { $0.cost <= casting.magicka && distance <= $0.range }
            .sorted { ($0.cost, $1.spell) > ($1.cost, $0.spell) }
            .first
    }

    /// A point `fleeDistance` away along target-to-actor, turned by `turn` radians. Turned,
    /// so a retry asks a new path and two fleeing actors scatter.
    public func fleePoint(turnedBy turn: Float, settings: CombatBehaviorSettings) -> SIMD3<Float> {
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
    public static func seed(for key: ReferenceKey) -> UInt64 {
        var state = ConditionRandom.defaultSeed
        for byte in key.description.utf8 {
            state = (state ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return state
    }
}
