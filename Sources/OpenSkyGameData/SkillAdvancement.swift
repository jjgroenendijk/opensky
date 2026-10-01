// Skill experience arithmetic from UESP "Skyrim:Leveling": what one use is worth,
// what the next level costs, and what a level-up adds toward the character
// level. The cost curve uses the level being left, as the wiki's worked example
// does. Documented in docs/engine/skill-advancement.md.

import Foundation
import OpenSkyFormatsESM

/// The two game settings skill advancement reads, resolved once.
///
/// Carried as a value rather than looked up per event, for the reason
/// `ActorValueLevelSettings` is: a fight that lands sixty blows must not walk
/// the GMST table sixty times, and a test must be able to state both numbers
/// without building a plugin.
nonisolated public struct SkillAdvancementSettings: Equatable, Sendable {
    /// `fSkillUseCurve` — the exponent the level-up threshold curves by,
    /// global to every skill.
    public var useCurve: Float
    /// `fXPPerSkillRank` — character experience banked per point of skill
    /// gained, multiplied by the skill level reached.
    public var characterExperiencePerRank: Float

    /// What UESP documents when no loaded plugin defines the setting.
    /// `fXPPerSkillRank` is in that position on this machine's install.
    public static let documentedDefaults = SkillAdvancementSettings(
        useCurve: 1.95,
        characterExperiencePerRank: 1
    )

    public static func resolve(store: GameSettingStore) -> SkillAdvancementSettings {
        var settings = SkillAdvancementSettings.documentedDefaults
        if
            case let .float(curve)? = store.setting(editorID: "fSkillUseCurve")?.setting.value,
            curve.isFinite, curve > 0
        {
            settings.useCurve = curve
        }
        if
            case let .float(perRank)? = store.setting(editorID: "fXPPerSkillRank")?
                .setting.value,
            perRank.isFinite, perRank >= 0
        {
            settings.characterExperiencePerRank = perRank
        }
        return settings
    }
}

/// What crossing one or more thresholds did to a skill.
nonisolated public struct SkillAdvanceOutcome: Equatable, Sendable {
    /// Whole skill points gained, zero when the experience did not reach the
    /// next threshold.
    public let levelsGained: Int
    /// The skill level afterwards.
    public let level: Float
    /// The experience left over, which stays on the skill toward its next
    /// level. Never negative.
    public let carriedExperience: Float
    /// What the level-ups banked toward the character's own level, summed over
    /// every point gained.
    public let characterExperience: Float

    public init(
        levelsGained: Int,
        level: Float,
        carriedExperience: Float,
        characterExperience: Float
    ) {
        self.levelsGained = levelsGained
        self.level = level
        self.carriedExperience = carriedExperience
        self.characterExperience = characterExperience
    }
}

nonisolated public enum SkillAdvancement: Sendable {
    /// The level a skill stops at. No plugin here authors it; UESP states it in prose
    /// ("reaching 100 in the appropriate skill", <https://en.uesp.net/wiki/Skyrim:Leveling>).
    /// Legendary resets are not modelled.
    public static let skillCeiling: Float = 100

    /// Most whole levels one advance may cross, so a script that hands over a
    /// preposterous magnitude cannot spin. Well above the 85 points a skill can
    /// actually gain, so it never truncates a legitimate advance.
    public static let maximumLevelsPerAdvance = 100

    /// Skill experience one use is worth: `Skill Use Mult * amount + Skill Use
    /// Offset`. `amount` is in "Skill Usage amounts"
    /// (<https://ck.uesp.net/wiki/AdvanceSkill_-_Game>). A zero, negative, or
    /// non-finite amount is worth nothing, offset included.
    public static func experience(
        forUse amount: Float,
        parameters: SkillUseParameters
    ) -> Float {
        guard amount.isFinite, amount > 0 else { return 0 }
        let multiplier = parameters.useMultiplier.isFinite ? parameters.useMultiplier : 0
        let offset = parameters.useOffset.isFinite ? parameters.useOffset : 0
        return max(0, multiplier * amount + offset)
    }

    /// The experience needed to leave `level` for the next one:
    /// `Skill Improve Mult * level ^ fSkillUseCurve + Skill Improve Offset`.
    /// - Returns: zero when the parameters make the threshold non-finite or not
    ///   positive. A caller reads that as "no advancement".
    public static func threshold(
        atSkillLevel level: Float,
        parameters: SkillUseParameters,
        settings: SkillAdvancementSettings = .documentedDefaults
    ) -> Float {
        guard level.isFinite, settings.useCurve.isFinite else { return 0 }
        let multiplier = parameters.improveMultiplier.isFinite
            ? parameters.improveMultiplier : 0
        let offset = parameters.improveOffset.isFinite ? parameters.improveOffset : 0
        let cost = multiplier * pow(max(0, level), settings.useCurve) + offset
        guard cost.isFinite, cost > 0 else { return 0 }
        return cost
    }

    /// What reaching skill level `level` banks toward the character's own
    /// level: `Skill level acquired * fXPPerSkillRank`.
    public static func characterExperience(
        forSkillLevel level: Float,
        settings: SkillAdvancementSettings = .documentedDefaults
    ) -> Float {
        guard level.isFinite, settings.characterExperiencePerRank.isFinite else { return 0 }
        return max(0, level * settings.characterExperiencePerRank)
    }

    /// Spends `experience` against the thresholds above `level`, one point at a time.
    /// The remainder carries, as the wiki's cumulative arithmetic implies. Experience
    /// equal to the threshold advances and carries nothing. At the ceiling nothing
    /// is gained or banked.
    public static func advance(
        experience: Float,
        from level: Float,
        parameters: SkillUseParameters,
        settings: SkillAdvancementSettings = .documentedDefaults
    ) -> SkillAdvanceOutcome {
        let start = level.isFinite ? max(0, level) : 0
        guard start < skillCeiling else {
            return SkillAdvanceOutcome(
                levelsGained: 0,
                level: min(start, skillCeiling),
                carriedExperience: 0,
                characterExperience: 0
            )
        }
        var current = start
        var remaining = experience.isFinite ? max(0, experience) : 0
        var gained = 0
        var banked: Float = 0
        while current < skillCeiling, gained < maximumLevelsPerAdvance {
            let cost = threshold(atSkillLevel: current, parameters: parameters, settings: settings)
            guard cost > 0, remaining >= cost else { break }
            remaining -= cost
            current += 1
            gained += 1
            banked += characterExperience(forSkillLevel: current, settings: settings)
        }
        return SkillAdvanceOutcome(
            levelsGained: gained,
            level: current,
            carriedExperience: current >= skillCeiling ? 0 : remaining,
            characterExperience: banked
        )
    }
}
