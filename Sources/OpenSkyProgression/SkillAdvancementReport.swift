// What skill advancement did and declined to do (issue #498, roadmap item
// 20.5): the per-advance report a caller reads and the session-wide tally a
// sweep asserts against.
//
// Split out of `PlayerProgressState.swift` when item 20.6 turned that file into
// the persisted character-level component: these two are session reporting and
// belong beside the runtime that produces them, not beside a save chunk.
//
// Documented in docs/engine/skill-advancement.md.

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
    /// session runs no character leveling (issue #499).
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

    public var levelsGained: Int {
        Int(level - previousLevel)
    }

    public var didAdvance: Bool {
        level > previousLevel
    }
}

/// What skill advancement did and declined to do.
///
/// Shaped like `PerkRuntimeTally`: every gap is a counter rather than a log
/// line, so a sweep asserts a number and a panel prints one.
nonisolated public struct SkillAdvancementTally: Equatable, Sendable {
    /// Uses converted into experience.
    public private(set) var uses = 0
    /// Skill points gained.
    public private(set) var advances = 0
    /// Uses dropped because the actor was not the player. Skills advance for
    /// the player only; an NPC's stay derived from its records.
    public private(set) var nonPlayerUses = 0
    /// Uses dropped because no skill claims the action — an unarmed strike, a
    /// blow taken in no armour, an effect whose MGEF names no magic skill.
    public private(set) var unclaimedUses = 0
    /// Uses dropped because this load order carries no AVIF advancement
    /// parameters for the skill, which is every synthetic session with no game
    /// data behind it.
    public private(set) var missingParameters = 0
    /// Uses dropped because the amount was zero, negative or not finite.
    public private(set) var emptyUses = 0
    /// Character levels gained by the points this runtime granted (issue #499).
    public private(set) var characterLevels = 0

    public var isClean: Bool {
        missingParameters == 0
    }

    public mutating func noteUse() {
        uses += 1
    }

    public mutating func noteAdvances(_ count: Int) {
        advances += max(0, count)
    }

    public mutating func noteNonPlayer() {
        nonPlayerUses += 1
    }

    public mutating func noteUnclaimed() {
        unclaimedUses += 1
    }

    public mutating func noteMissingParameters() {
        missingParameters += 1
    }

    public mutating func noteEmpty() {
        emptyUses += 1
    }

    public mutating func noteCharacterLevels(_ count: Int) {
        characterLevels += max(0, count)
    }
}
