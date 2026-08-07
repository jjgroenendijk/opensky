// Base health / magicka / stamina for one actor (issue #194, roadmap item
// 15.3): race starting attributes, the ACBS offsets, and — for an auto-calc
// actor — the per-level points its class spreads across the three.
//
// Every rule here is quoted from an open source rather than inferred:
//
//   "Calculated Health: The Actor's adjusted health (Base + Offset)", where
//   "Base Health: The Actor's calculated base health, as determined by their
//   Race, Class, and Level." (<https://ck.uesp.net/wiki/Stats_Tab>)
//
//   "If the auto-calc flag for an NPC isn't set, all attributes are calculated
//   just as: Attribute = [Racial bonus] + [NPC offset]."
//   (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CLAS>)
//
//   "Attribute = [Racial bonus] + [NPC offset] + 10*(Level-1)/(Sum of class'
//   attribute weights)*[Attribute weight]", and "The only difference for health
//   is that health always receives an additional 5 points per level, regardless
//   of the class weights". (Same page.) The two constants are the
//   `iAVDhmsLevelUp` and `fNPCHealthLevelBonus` game settings, named as such by
//   the Creation Kit: "all Actors gain 10 points to distribute per level (this
//   value comes from the iAVDhmsLevelUp game setting) ... NPC's get a bonus
//   amount of health per level as set by the fNPCHealthLevelBonus game setting;
//   by default this is 5." (<https://ck.uesp.net/wiki/Class>)
//
//   The apportionment is not a plain multiply-and-round. "The exact method used
//   to assign values" is to hand out every complete set of points first —
//   `floor(points / sum of weights) * weight` each — and then give the leftover
//   out one at a time, looping over the attributes "ordered first in decreasing
//   order of weight" with ties broken "in reverse actor value index order
//   (stamina, magicka, then health)", never taking an attribute past its own
//   weight in a single leftover pass. (UESP CLAS, "Attributes" and "Skills".)
//
// The Creation Kit's own worked example uses the opposite tie order (health
// first) but reaches the same numbers on every case documented on either page,
// because ties only matter when the leftover runs out mid-pass. Where they
// diverge OpenSky follows UESP, which states its rule as the exact method
// rather than as a procedure for hand-calculation.
//
// Documented in docs/engine/actor-values.md.

import Foundation

/// The two game settings the per-level derivation reads, resolved once.
///
/// Carried as a value rather than looked up per actor: deriving stats for a
/// cell full of actors must not walk the GMST table a thousand times, and a
/// test must be able to state both numbers without building a plugin.
nonisolated struct ActorValueLevelSettings: Equatable, Sendable {
    /// `iAVDhmsLevelUp` — points spread across the three attributes per level
    /// above 1.
    var pointsPerLevel: Int
    /// `fNPCHealthLevelBonus` — extra health per level above 1, outside the
    /// weighted spread.
    var healthBonusPerLevel: Float

    /// The values the Creation Kit documents as the defaults, used when no
    /// loaded plugin defines the setting.
    static let documentedDefaults = ActorValueLevelSettings(
        pointsPerLevel: 10,
        healthBonusPerLevel: 5
    )

    static func resolve(store: GameSettingStore) -> ActorValueLevelSettings {
        var settings = ActorValueLevelSettings.documentedDefaults
        if case let .integer(points)? = store.setting(editorID: "iAVDhmsLevelUp")?.setting.value {
            settings.pointsPerLevel = max(0, Int(points))
        }
        if
            case let .float(bonus)? = store.setting(editorID: "fNPCHealthLevelBonus")?
                .setting.value,
            bonus.isFinite
        {
            settings.healthBonusPerLevel = max(0, bonus)
        }
        return settings
    }
}

/// Everything the derivation needs about one actor, gathered from the records
/// its template chain resolves to.
nonisolated struct ActorValueInputs: Equatable, Sendable {
    /// RACE DATA starting attributes, from the traits-resolved race.
    var race: Race.Stats
    /// ACBS offsets and level words, from the stats-resolved NPC_.
    var stats: ActorBase.Stats
    /// Whether stats come from race + class + level rather than race + offset.
    var autoCalculatesStats: Bool
    /// Whether the level word is a player-level multiplier.
    var usesPlayerLevelMultiplier: Bool
    /// CLAS attribute weights, zero when the actor names no class.
    var attributeWeights: CharacterClass.AttributeWeights

    init(
        race: Race.Stats = Race.Stats(),
        stats: ActorBase.Stats = ActorBase.Stats(),
        autoCalculatesStats: Bool = false,
        usesPlayerLevelMultiplier: Bool = false,
        attributeWeights: CharacterClass.AttributeWeights = CharacterClass.AttributeWeights()
    ) {
        self.race = race
        self.stats = stats
        self.autoCalculatesStats = autoCalculatesStats
        self.usesPlayerLevelMultiplier = usesPlayerLevelMultiplier
        self.attributeWeights = attributeWeights
    }
}

nonisolated enum ActorValueDerivation {
    /// The actor's effective level.
    ///
    /// A fixed-level actor uses the ACBS level word directly. A `PC Level Mult`
    /// actor multiplies the player's level by the word over 1000 and clamps the
    /// result to Calc Min / Calc Max: "Level Mult: The level of the player is
    /// multiplied by this field to determine the level of the NPC. Calc Min:
    /// The NPC's minimum level. Calc Max: The NPC's maximum level."
    /// (<https://ck.uesp.net/wiki/Stats_Tab>)
    ///
    /// A zero bound means unbounded rather than "level 0": the Creation Kit
    /// leaves both fields at zero when the designer sets no clamp, and vanilla
    /// records rely on that. Every level floors at 1, which is the level the
    /// race's starting attributes are defined for.
    static func level(inputs: ActorValueInputs, playerLevel: Int) -> Int {
        guard inputs.usesPlayerLevelMultiplier else {
            return max(1, Int(inputs.stats.levelWord))
        }
        let multiplier = Double(inputs.stats.levelWord) / 1000
        let scaled = Int((Double(max(1, playerLevel)) * multiplier).rounded())
        var level = max(1, scaled)
        if inputs.stats.calcMinLevel > 0 {
            level = max(level, Int(inputs.stats.calcMinLevel))
        }
        if inputs.stats.calcMaxLevel > 0 {
            level = min(level, Int(inputs.stats.calcMaxLevel))
        }
        return max(1, level)
    }

    /// Base health, magicka and stamina for one actor.
    ///
    /// - Parameters:
    ///   - playerLevel: only read when the actor uses `PC Level Mult`. There is
    ///     no player level system before M18, so callers pass 1 and get the
    ///     bottom of every scaled actor's range — deliberately the low end
    ///     rather than a guess at the middle.
    static func baseValues(
        inputs: ActorValueInputs,
        settings: ActorValueLevelSettings = .documentedDefaults,
        playerLevel: Int = 1
    ) -> ActorValues {
        let offsets = ActorValues(
            health: Float(inputs.stats.healthOffset),
            magicka: Float(inputs.stats.magickaOffset),
            stamina: Float(inputs.stats.staminaOffset)
        )
        let racial = ActorValues(
            health: finite(inputs.race.startingHealth),
            magicka: finite(inputs.race.startingMagicka),
            stamina: finite(inputs.race.startingStamina)
        )
        guard inputs.autoCalculatesStats else {
            return sum(racial, offsets).clampedToNonNegative()
        }
        let levelsGained = max(0, level(inputs: inputs, playerLevel: playerLevel) - 1)
        let spread = distribute(
            points: settings.pointsPerLevel * levelsGained,
            weights: inputs.attributeWeights
        )
        var perLevel = spread
        perLevel.health += settings.healthBonusPerLevel * Float(levelsGained)
        return sum(sum(racial, offsets), perLevel).clampedToNonNegative()
    }

    /// Spreads `points` across the three attributes by their class weights,
    /// following UESP's exact method (see the file header).
    ///
    /// Returns whole points as an `ActorValues` triple — every value is an
    /// integer, and they always sum to `points` when the weights are not all
    /// zero, so no point is silently lost to rounding. A class with no
    /// weights spreads nothing, which is what a record with a zero-weight DATA
    /// or no class at all should do — the alternative, dividing by zero, would
    /// put a NaN into an actor's maximum health.
    static func distribute(
        points: Int,
        weights: CharacterClass.AttributeWeights
    ) -> ActorValues {
        let total = weights.sum
        guard points > 0, total > 0 else { return .zero }
        let byKind: [ActorValueKind: Int] = [
            .health: Int(weights.health),
            .magicka: Int(weights.magicka),
            .stamina: Int(weights.stamina)
        ]
        let sets = points / total
        var awarded: [ActorValueKind: Int] = [:]
        for (kind, weight) in byKind {
            awarded[kind] = sets * weight
        }
        var leftover = points - sets * total
        // Decreasing weight, ties in reverse actor-value index order — stamina,
        // then magicka, then health. Spelled as a total order rather than as a
        // stable sort of a reversed list, because `sorted(by:)` is not
        // documented to be stable and the tie rule is exactly what decides
        // where an odd leftover point lands.
        let reverseIndex: [ActorValueKind: Int] = [.stamina: 0, .magicka: 1, .health: 2]
        let order = ActorValueKind.allCases.sorted { lhs, rhs in
            let left = byKind[lhs] ?? 0
            let right = byKind[rhs] ?? 0
            if left != right {
                return left > right
            }
            return (reverseIndex[lhs] ?? 0) < (reverseIndex[rhs] ?? 0)
        }
        var taken: [ActorValueKind: Int] = [:]
        while leftover > 0 {
            var progressed = false
            for kind in order where leftover > 0 {
                let weight = byKind[kind] ?? 0
                guard (taken[kind] ?? 0) < weight else { continue }
                taken[kind, default: 0] += 1
                awarded[kind, default: 0] += 1
                leftover -= 1
                progressed = true
            }
            // Unreachable while the leftover is below the weight sum, which it
            // always is by construction. Guards the loop anyway: a silent hang
            // is the one failure mode worse than a wrong number.
            guard progressed else { break }
        }
        var spread = ActorValues.zero
        for kind in ActorValueKind.allCases {
            spread[kind] = Float(awarded[kind] ?? 0)
        }
        return spread
    }

    // MARK: - Private

    private static func sum(_ lhs: ActorValues, _ rhs: ActorValues) -> ActorValues {
        ActorValues(
            health: lhs.health + rhs.health,
            magicka: lhs.magicka + rhs.magicka,
            stamina: lhs.stamina + rhs.stamina
        )
    }

    private static func finite(_ value: Float) -> Float {
        value.isFinite ? value : 0
    }
}

nonisolated extension ActorValues {
    /// A negative offset can out-weigh a small racial base. The game has no
    /// concept of a negative maximum, and one would make every fraction the HUD
    /// asks for meaningless, so the floor is zero.
    fileprivate func clampedToNonNegative() -> ActorValues {
        ActorValues(
            health: max(0, health.isFinite ? health : 0),
            magicka: max(0, magicka.isFinite ? magicka : 0),
            stamina: max(0, stamina.isFinite ? stamina : 0)
        )
    }
}
