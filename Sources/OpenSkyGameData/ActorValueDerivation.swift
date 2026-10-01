// Base health, magicka and stamina: race bonus + ACBS offset, plus for auto-calc
// actors 10 points per level (`iAVDhmsLevelUp`) spread by class weight, and health
// +5 per level (`fNPCHealthLevelBonus`). Leftover points go one at a time by weight,
// ties in reverse index order, per UESP's exact method
// (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CLAS>,
// <https://ck.uesp.net/wiki/Class>). See docs/engine/actor-values.md.

import Foundation
import OpenSkyFormatsESM

/// The two game settings the per-level derivation reads, resolved once.
///
/// Carried as a value rather than looked up per actor: deriving stats for a
/// cell full of actors must not walk the GMST table a thousand times, and a
/// test must be able to state both numbers without building a plugin.
nonisolated public struct ActorValueLevelSettings: Equatable, Sendable {
    /// `iAVDhmsLevelUp` — points spread across the three attributes per level
    /// above 1.
    public var pointsPerLevel: Int
    /// `fNPCHealthLevelBonus` — extra health per level above 1, outside the
    /// weighted spread.
    public var healthBonusPerLevel: Float
    /// `iAVDSkillsLevelUp`: skill points per level above 1, "the fixed 8"
    /// (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CLAS>).
    public var skillPointsPerLevel = 8

    /// The values the Creation Kit documents as the defaults, used when no
    /// loaded plugin defines the setting.
    public static let documentedDefaults = ActorValueLevelSettings(
        pointsPerLevel: 10,
        healthBonusPerLevel: 5,
        skillPointsPerLevel: 8
    )

    public static func resolve(store: GameSettingStore) -> ActorValueLevelSettings {
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
        if
            case let .integer(points)? = store.setting(editorID: "iAVDSkillsLevelUp")?
                .setting.value
        {
            settings.skillPointsPerLevel = max(0, Int(points))
        }
        return settings
    }
}

/// Everything the derivation needs about one actor, gathered from the records
/// its template chain resolves to.
nonisolated public struct ActorValueInputs: Equatable, Sendable {
    /// RACE DATA starting attributes, from the traits-resolved race.
    public var race: Race.Stats
    /// ACBS offsets and level words, from the stats-resolved NPC_.
    public var stats: ActorBase.Stats
    /// Whether stats come from race + class + level rather than race + offset.
    public var autoCalculatesStats: Bool
    /// Whether the level word is a player-level multiplier.
    public var usesPlayerLevelMultiplier: Bool
    /// CLAS attribute weights, zero when the actor names no class.
    public var attributeWeights: CharacterClass.AttributeWeights
    /// CLAS skill weights, empty when the actor names no class.
    public var skillWeights: CharacterClass.SkillWeights

    public init(
        race: Race.Stats = Race.Stats(),
        stats: ActorBase.Stats = ActorBase.Stats(),
        autoCalculatesStats: Bool = false,
        usesPlayerLevelMultiplier: Bool = false,
        attributeWeights: CharacterClass.AttributeWeights = CharacterClass.AttributeWeights(),
        skillWeights: CharacterClass.SkillWeights = CharacterClass.SkillWeights()
    ) {
        self.race = race
        self.stats = stats
        self.autoCalculatesStats = autoCalculatesStats
        self.usesPlayerLevelMultiplier = usesPlayerLevelMultiplier
        self.attributeWeights = attributeWeights
        self.skillWeights = skillWeights
    }
}

nonisolated public enum ActorValueDerivation: Sendable {
    /// The actor's effective level. `PC Level Mult` scales the player's level by the
    /// word / 1000, clamped to Calc Min / Max (<https://ck.uesp.net/wiki/Stats_Tab>).
    /// A zero bound means no bound. The level floors at 1.
    public static func level(inputs: ActorValueInputs, playerLevel: Int) -> Int {
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

    /// Base health, magicka and stamina for one actor. `playerLevel` is read only
    /// for `PC Level Mult` actors.
    public static func baseValues(
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

    /// Spreads `points` across the three attributes by class weight (file header).
    /// The whole points always sum to `points`. Zero weights spread nothing, which
    /// avoids a divide by zero and a NaN maximum.
    public static func distribute(
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
