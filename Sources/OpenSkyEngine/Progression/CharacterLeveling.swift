// Character level arithmetic (issue #499, roadmap item 20.6): what the next
// character level costs, what a total of character experience is worth in
// levels, and what one level-up hands the player.
//
// Pure functions over numbers, in the shape `SkillAdvancement` takes: nothing
// here reaches the world, so every assertion about the curve is plain
// arithmetic rather than something only a running session shows.
//
// ## The curve, quoted
//
// UESP "Skyrim:Leveling" states it twice, once in plain numbers and once in the
// settings those numbers come from:
//
//   XP required to level up your character = (Current level + 3) * 25
//
//   Or if using the Skyrim Creation Kit Game Setting values:
//   (fXPLevelUpBase)+(Current Char. Level * fXPLevelUpMult)
//   Where the default values for Skyrim vanilla (1.9.32.X) are
//   fXPLevelUpBase = 75 and fXPLevelUpMult = 25.
//
// and pins both ends of it with worked numbers: "100 XP is required to advance
// from level 1 to level 2, and 1300 XP is required to advance from level 49 to
// 50. This is consistent across all levels."
//
// The same page gives the closed form of the running total and its inverse:
//
//   XP required to go from level 1 to level N = 12.5 * N^2 + 62.5 * N - 75
//   FLOOR(-2.5 + SQRT(8 * XP + 1225) / 10)
//
// Both are the vanilla-numbers spelling of the same curve rather than a second
// rule, so they are implemented here from the settings and *checked* against
// those constants in `CharacterLevelingTests` — a load order that moves either
// setting moves the sum with it, which a hardcoded 12.5 could not do.
//
// ## Where the numbers come from
//
// `fXPLevelUpBase` 75 and `fXPLevelUpMult` 25 are authored by `Skyrim.esm` on
// this machine, read 2026-08-20 with `openskycli gmst list --prefix fxp`, and
// pinned by `CharacterLevelingRealDataTests`. So are the two settings the
// level-up *reward* reads: `iAVDhmsLevelUp` 10, the points one attribute pick
// adds, and `fLevelUpCarryWeightMod` 5, the carry weight a stamina pick adds.
//
// Documented in docs/engine/character-leveling.md.

import Foundation

/// The four game settings character leveling reads, resolved once.
///
/// Carried as a value rather than looked up per level-up, for the reason
/// `SkillAdvancementSettings` is: a test must be able to state every number
/// without building a plugin, and a session must not walk the GMST table to
/// answer what the next level costs.
nonisolated struct CharacterLevelSettings: Equatable, Sendable {
    /// `fXPLevelUpBase` — the constant term of the level-up threshold.
    var levelUpBase: Float
    /// `fXPLevelUpMult` — what each level already held adds to the threshold.
    var levelUpMultiplier: Float
    /// `iAVDhmsLevelUp` — points one attribute pick adds to the chosen value.
    /// "One attribute (Health, Magicka, Stamina) can be increased by 10 points"
    /// (<https://en.uesp.net/wiki/Skyrim:Leveling>).
    ///
    /// The same setting `ActorValueLevelSettings.pointsPerLevel` reads for an
    /// NPC, where it is the number of points a *class* spreads across the three
    /// rather than the number one pick puts into one. Two readings of one
    /// setting, both stated by the sources, and neither derived from the other.
    var attributeIncrement: Float
    /// `fLevelUpCarryWeightMod` — carry weight a stamina pick adds on top of
    /// the stamina itself. "Adding to your base stamina when you level up
    /// increases your carry weight by 5"
    /// (<https://en.uesp.net/wiki/Skyrim:Stamina>).
    var carryWeightPerStaminaPick: Float

    /// What UESP documents for vanilla, which is also what this machine's
    /// `Skyrim.esm` authors for all four.
    static let documentedDefaults = CharacterLevelSettings(
        levelUpBase: 75,
        levelUpMultiplier: 25,
        attributeIncrement: 10,
        carryWeightPerStaminaPick: 5
    )

    static func resolve(store: GameSettingStore) -> CharacterLevelSettings {
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
nonisolated struct CharacterLevelOutcome: Equatable, Sendable {
    /// Whole character levels gained, zero when the experience did not reach
    /// the next threshold.
    let levelsGained: Int
    /// The character level afterwards.
    let level: Int
    /// The experience left over, which stays banked toward the next level.
    /// Never negative.
    let carriedExperience: Float

    var didAdvance: Bool {
        levelsGained > 0
    }
}

nonisolated enum CharacterLeveling {
    /// Most whole levels one award may cross, so a script handing over a
    /// preposterous magnitude cannot spin. Far above the level any documented
    /// play reaches, so it never truncates a legitimate award.
    static let maximumLevelsPerAward = 1000

    /// The experience needed to leave `level` for the next one:
    /// `fXPLevelUpBase + level * fXPLevelUpMult`.
    ///
    /// - Returns: zero for a threshold the settings make impossible — a
    ///   non-finite result, or one at or below zero. A caller reads that as "no
    ///   leveling", which is the safe answer: treating it as free would run the
    ///   player to the level cap on the first skill point.
    static func experienceForNextLevel(
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

    /// The experience one character starting at level 1 must earn in total to
    /// reach `level`, which is the sum of every threshold below it.
    ///
    /// Summed rather than closed-form on purpose: the closed form UESP prints
    /// is the vanilla-numbers spelling of this sum, and a load order that moves
    /// either setting moves the sum with it. `CharacterLevelingTests` checks
    /// this against `12.5 * N^2 + 62.5 * N - 75` at the vanilla settings, which
    /// is what makes the two readings one fact rather than two.
    static func cumulativeExperience(
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

    /// Spends `experience` against the thresholds above `level`, one whole
    /// level at a time.
    ///
    /// The remainder carries, which is the rule behind UESP's own note that
    /// over-training banks levels rather than wasting the surplus: "Over-
    /// training will still grant you level ups even if the progress bar is
    /// stuck at 100% (for example: If you start training Illusion from level 1
    /// to Illusion level 44 you will be level 6 once you choose to level up)"
    /// (<https://en.uesp.net/wiki/Skyrim:Leveling>). Experience exactly equal
    /// to the threshold levels the character and carries nothing.
    static func advance(
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
