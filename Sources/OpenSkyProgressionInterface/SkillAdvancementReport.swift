import Foundation

/// One recorded use, after it was converted, stored and possibly spent.
nonisolated public struct SkillAdvanceReport: Equatable, Sendable {
    /// The skill that was credited.
    public let skill: Int32
    /// Skill experience this use was worth.
    public let experience: Float
    /// The skill's level before and after, which differ only when a threshold
    /// was crossed.
    public let previousLevel: Float
    public let level: Float
    /// Experience left on the skill toward its next level.
    public let carriedExperience: Float
    /// What the level-up banked toward the character's own level, zero when
    /// nothing levelled.
    public let characterExperience: Float
    /// What banking that experience did to the character level, or nil when the
    /// session runs no character leveling.
    public let levelUp: PlayerLevelUpReport?

    public init(
        skill: Int32,
        experience: Float,
        previousLevel: Float,
        level: Float,
        carriedExperience: Float,
        characterExperience: Float,
        levelUp: PlayerLevelUpReport? = nil
    ) {
        self.skill = skill
        self.experience = experience
        self.previousLevel = previousLevel
        self.level = level
        self.carriedExperience = carriedExperience
        self.characterExperience = characterExperience
        self.levelUp = levelUp
    }

    public var didAdvance: Bool {
        level > previousLevel
    }
}
