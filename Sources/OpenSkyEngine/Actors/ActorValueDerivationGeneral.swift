// Record-authored *non-primary* actor values for one actor (issue #468,
// roadmap item 19.5): the baselines an actor has before the session touches
// anything, for the 161 values outside health, magicka and stamina.
//
// A satellite of `ActorValueDerivation.swift` rather than more of it, following
// the `RendererScenePass` split rule: that file holds the primary formula and
// is at its size shape.
//
// Every rule here is quoted from an open source, as the primary formula's are:
//
//   "Skill = 15 + [Racial bonus] + 8*(Level-1)/(Sum of class' skill
//   weights)*[Skill weight]", with the leftover points assigned "one at a time
//   by looping over all the skills in order. Skills are ordered first by their
//   weight (higher skills ordered first) and second by their actor value index
//   (lower indices are ordered first)."
//   (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CLAS>) Note the tie
//   rule is the *opposite* of the attribute one, which breaks ties in reverse
//   index order; both are transcribed as stated rather than unified.
//
//   RACE DATA authors four numbers that are actor values by name: the seven
//   "Racial bonus for skill N" bytes, "Base Carry Weight", "Base Mass" and
//   "Unarmed Damage" (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/RACE>).
//
//   NPC_ ACBS authors one more: "Speed Multiplier"
//   (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/NPC_>), which is
//   actor value 30, `Speed Mult`.
//
// ## What is deliberately not read
//
// NPC_ DNAM carries "18 base skills, 18 skill mods". Neither this file nor the
// docs claim to know how those two arrays combine — no open source distinguishes
// them, and the CLAS formula above is stated as approximate ("generally only be
// accurate to within a couple points") so it cannot settle the question either.
// Storing a number whose provenance is unresolved is worse than reading the
// documented floor, so the skill baselines here come from the formula and the
// DNAM block waits for M20's skill work with a real-data comparison behind it.
//
// Documented in docs/engine/actor-values.md.

import Foundation

nonisolated extension ActorValueDerivation {
    /// Base values for every non-primary actor value one actor's records
    /// author, keyed by vanilla table index.
    ///
    /// Sparse: an index absent from the result reads
    /// `ActorValueIdentity.defaultValue(at:)`, so this carries only what a
    /// record actually said. The eighteen skills are always present, because
    /// the race bonus and the class spread both apply on top of a floor that is
    /// itself documented rather than assumed.
    static func generalBaseValues(
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
    static func skillBaseValues(
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

    /// Spreads `points` across the eighteen skills by their class weights,
    /// following the exact method UESP states (see the file header): whole sets
    /// first, then the leftover one point at a time in decreasing weight order
    /// with ties broken by ascending actor-value index, never taking a skill
    /// past its own weight in a single pass.
    ///
    /// Returns whole points per index, omitting the skills that got none. A
    /// class with no weights spreads nothing, which is what a class record
    /// with a zero-weight DATA or no class at all should do.
    static func distributeSkillPoints(
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
nonisolated enum ActorValueIndex {
    static let speedMult: Int32 = 30
    static let carryWeight: Int32 = 32
    static let unarmedDamage: Int32 = 35
    static let mass: Int32 = 36
    static let damageResist: Int32 = 39
    static let poisonResist: Int32 = 40
    static let resistFire: Int32 = 41
    static let resistShock: Int32 = 42
    static let resistFrost: Int32 = 43
    static let resistMagic: Int32 = 44
    static let resistDisease: Int32 = 45
}
