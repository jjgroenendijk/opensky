// Character level arithmetic: the cost of the next level, the levels a total of
// experience is worth, and what a level-up grants. Pure functions. The curve is
// `fXPLevelUpBase + level * fXPLevelUpMult` (UESP "Skyrim:Leveling"; vanilla 75
// and 25). `CharacterLevelingTests` checks the running total against UESP's
// closed form. See docs/engine/character-leveling.md.

import Foundation
import OpenSkyFormatsESM

/// The four game settings character leveling reads, resolved once.
///
/// Carried as a value rather than looked up per level-up, for the reason
/// `SkillAdvancementSettings` is: a test must be able to state every number
/// without building a plugin, and a session must not walk the GMST table to
/// answer what the next level costs.
nonisolated public struct CharacterLevelSettings: Equatable, Sendable {
    /// `fXPLevelUpBase` — the constant term of the level-up threshold.
    public var levelUpBase: Float
    /// `fXPLevelUpMult` — what each level already held adds to the threshold.
    public var levelUpMultiplier: Float
    /// `iAVDhmsLevelUp`: points one attribute pick adds. "One attribute (Health,
    /// Magicka, Stamina) can be increased by 10 points"
    /// (<https://en.uesp.net/wiki/Skyrim:Leveling>). For an NPC the same setting is
    /// the points a class spreads (`ActorValueLevelSettings.pointsPerLevel`).
    public var attributeIncrement: Float
    /// `fLevelUpCarryWeightMod` — carry weight a stamina pick adds on top of
    /// the stamina itself. "Adding to your base stamina when you level up
    /// increases your carry weight by 5"
    /// (<https://en.uesp.net/wiki/Skyrim:Stamina>).
    public var carryWeightPerStaminaPick: Float

    /// What UESP documents for vanilla, which is also what this machine's
    /// `Skyrim.esm` authors for all four.
    public static let documentedDefaults = CharacterLevelSettings(
        levelUpBase: 75,
        levelUpMultiplier: 25,
        attributeIncrement: 10,
        carryWeightPerStaminaPick: 5
    )

    public static func resolve(store: GameSettingStore) -> CharacterLevelSettings {
        var settings = CharacterLevelSettings.documentedDefaults
        if let base = Self.number(store, "fXPLevelUpBase"), base >= 0 {
            settings.levelUpBase = base
        }
        if let multiplier = Self.number(store, "fXPLevelUpMult"), multiplier >= 0 {
            settings.levelUpMultiplier = multiplier
        }
        if let increment = Self.number(store, "iAVDhmsLevelUp"), increment >= 0 {
            settings.attributeIncrement = increment
        }
        if let carry = Self.number(store, "fLevelUpCarryWeightMod"), carry >= 0 {
            settings.carryWeightPerStaminaPick = carry
        }
        return settings
    }

    /// One setting as a finite float, whichever of the two numeric spellings
    /// the record used. `iAVDhmsLevelUp` is an integer setting and the other
    /// three are floats, so reading only one tag would silently drop the
    /// attribute increment to its fallback on an install that authors it.
    private static func number(_ store: GameSettingStore, _ editorID: String) -> Float? {
        switch store.setting(editorID: editorID)?.setting.value {
        case let .float(value): value.isFinite ? value : nil
        case let .integer(value): Float(value)
        default: nil
        }
    }
}

/// What spending character experience against the curve did.
nonisolated public struct CharacterLevelOutcome: Equatable, Sendable {
    /// Whole character levels gained, zero when the experience did not reach
    /// the next threshold.
    public let levelsGained: Int
    /// The character level afterwards.
    public let level: Int
    /// The experience left over, which stays banked toward the next level.
    /// Never negative.
    public let carriedExperience: Float

    public var didAdvance: Bool {
        levelsGained > 0
    }
}

nonisolated public enum CharacterLeveling: Sendable {
    /// Most whole levels one award may cross, so a script handing over a
    /// preposterous magnitude cannot spin. Far above the level any documented
    /// play reaches, so it never truncates a legitimate award.
    public static let maximumLevelsPerAward = 1000

    /// The experience needed to leave `level` for the next one:
    /// `fXPLevelUpBase + level * fXPLevelUpMult`.
    /// - Returns: zero when the settings make the threshold non-finite or not
    ///   positive. A caller reads that as "no leveling".
    public static func experienceForNextLevel(
        atLevel level: Int,
        settings: CharacterLevelSettings = .documentedDefaults
    ) -> Float {
        guard settings.levelUpBase.isFinite, settings.levelUpMultiplier.isFinite else {
            return 0
        }
        let cost = settings.levelUpBase
            + Float(max(PlayerLevelSource.startingLevel, level)) * settings.levelUpMultiplier
        guard cost.isFinite, cost > 0 else { return 0 }
        return cost
    }

    /// The total experience needed from level 1 to reach `level`: the sum of the
    /// thresholds below it. Summed, not closed-form, so changed settings apply;
    /// `CharacterLevelingTests` checks it against `12.5 * N^2 + 62.5 * N - 75`.
    public static func cumulativeExperience(
        toLevel level: Int,
        settings: CharacterLevelSettings = .documentedDefaults
    ) -> Float {
        var total: Float = 0
        var current = PlayerLevelSource.startingLevel
        while current < level {
            let cost = experienceForNextLevel(atLevel: current, settings: settings)
            guard cost > 0 else { break }
            total += cost
            current += 1
        }
        return total
    }

    /// Spends `experience` against the thresholds above `level`, one level at a time.
    /// The remainder carries, so over-training banks levels
    /// (<https://en.uesp.net/wiki/Skyrim:Leveling>). Experience equal to the
    /// threshold levels up and carries nothing.
    public static func advance(
        experience: Float,
        from level: Int,
        settings: CharacterLevelSettings = .documentedDefaults
    ) -> CharacterLevelOutcome {
        var current = max(PlayerLevelSource.startingLevel, level)
        var remaining = experience.isFinite ? max(0, experience) : 0
        var gained = 0
        while gained < maximumLevelsPerAward {
            let cost = experienceForNextLevel(atLevel: current, settings: settings)
            guard cost > 0, remaining >= cost else { break }
            remaining -= cost
            current += 1
            gained += 1
        }
        return CharacterLevelOutcome(
            levelsGained: gained,
            level: current,
            carriedExperience: remaining
        )
    }
}
