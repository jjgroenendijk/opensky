// Record-authored non-primary actor values. Skills are 15 + race bonus + 8 points
// per level spread by class weight, leftovers by weight with ties in ascending index
// order (UESP CLAS; the opposite of the attribute rule). RACE DATA and NPC_ ACBS give
// carry weight, mass, unarmed damage and `Speed Mult`. NPC_ DNAM skills are not read:
// no source says how its two arrays combine. See docs/engine/actor-values.md.

import Foundation
import OpenSkyFormatsESM

nonisolated extension ActorValueDerivation {
    /// Base values for every non-primary value the records author, by table index.
    /// Sparse: a missing index reads `ActorValueIdentity.defaultValue(at:)`. The
    /// eighteen skills are always present.
    public static func generalBaseValues(
        inputs: ActorValueInputs,
        settings: ActorValueLevelSettings = .documentedDefaults,
        playerLevel: Int = 1
    ) -> [Int32: Float] {
        var values = skillBaseValues(
            inputs: inputs,
            settings: settings,
            playerLevel: playerLevel
        )
        values[ActorValueIndex.speedMult] = Float(inputs.stats.speedMultiplier)
        values[ActorValueIndex.carryWeight] = finite(inputs.race.baseCarryWeight)
        values[ActorValueIndex.unarmedDamage] = finite(inputs.race.unarmedDamage)
        values[ActorValueIndex.mass] = finite(inputs.race.baseMass)
        return values
    }

    /// The eighteen skills: the documented floor, the race's bonuses, and — for
    /// an auto-calc actor — the class's spread of the per-level skill points.
    public static func skillBaseValues(
        inputs: ActorValueInputs,
        settings: ActorValueLevelSettings = .documentedDefaults,
        playerLevel: Int = 1
    ) -> [Int32: Float] {
        var values: [Int32: Float] = [:]
        for index in ActorValueIdentity.firstSkillIndex ... ActorValueIdentity.lastSkillIndex {
            values[index] = ActorValueIdentity.skillFloor
        }
        for bonus in inputs.race.skillBonuses where ActorValueIdentity.isVanilla(
            index: bonus.actorValue
        ) {
            values[bonus.actorValue, default: 0] += finite(bonus.bonus)
        }
        guard inputs.autoCalculatesStats else { return values }
        let levelsGained = max(0, level(inputs: inputs, playerLevel: playerLevel) - 1)
        let spread = distributeSkillPoints(
            points: settings.skillPointsPerLevel * levelsGained,
            weights: inputs.skillWeights
        )
        for (index, points) in spread {
            values[index, default: 0] += Float(points)
        }
        return values
    }

    /// Spreads `points` across the eighteen skills by class weight (file header).
    /// Returns whole points per index, omitting zeros. Zero weights spread nothing.
    public static func distributeSkillPoints(
        points: Int,
        weights: CharacterClass.SkillWeights
    ) -> [Int32: Int] {
        let total = weights.sum
        guard points > 0, total > 0 else { return [:] }
        let weighted = weights.byActorValue.filter { $0.weight > 0 }
        let sets = points / total
        var awarded: [Int32: Int] = [:]
        for entry in weighted {
            awarded[entry.index] = sets * entry.weight
        }
        var leftover = points - sets * total
        let order = weighted.sorted { lhs, rhs in
            lhs.weight != rhs.weight ? lhs.weight > rhs.weight : lhs.index < rhs.index
        }
        var taken: [Int32: Int] = [:]
        while leftover > 0 {
            var progressed = false
            for entry in order where leftover > 0 {
                guard (taken[entry.index] ?? 0) < entry.weight else { continue }
                taken[entry.index, default: 0] += 1
                awarded[entry.index, default: 0] += 1
                leftover -= 1
                progressed = true
            }
            // Unreachable while the leftover is below the weight sum, which it
            // always is by construction. Guards the loop anyway, for the reason
            // the attribute spread does: a silent hang is the one failure mode
            // worse than a wrong number.
            guard progressed else { break }
        }
        return awarded.filter { $0.value > 0 }
    }

    private static func finite(_ value: Float) -> Float {
        value.isFinite ? max(0, value) : 0
    }
}

/// The handful of vanilla actor-value indices this engine names in code.
///
/// Spelled once here rather than as literals at four call sites, and numbered
/// from `ActorValueIdentity.vanillaNames` — index 30 is `Speed Mult` because
/// that table says so, not because anything recalled it.
nonisolated public enum ActorValueIndex: Sendable {
    public static let speedMult: Int32 = 30
    public static let carryWeight: Int32 = 32
    public static let unarmedDamage: Int32 = 35
    public static let mass: Int32 = 36
    public static let damageResist: Int32 = 39
    public static let poisonResist: Int32 = 40
    public static let resistFire: Int32 = 41
    public static let resistShock: Int32 = 42
    public static let resistFrost: Int32 = 43
    public static let resistMagic: Int32 = 44
    public static let resistDisease: Int32 = 45
}
