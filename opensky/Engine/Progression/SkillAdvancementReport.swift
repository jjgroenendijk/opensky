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
nonisolated struct SkillAdvanceReport: Equatable, Sendable {
    /// The skill that was credited.
    let skill: Int32
    /// Skill experience this use was worth.
    let experience: Float
    /// The skill's level before and after, which differ only when a threshold
    /// was crossed.
    let previousLevel: Float
    let level: Float
    /// Experience left on the skill toward its next level.
    let carriedExperience: Float
    /// What the level-up banked toward the character's own level, zero when
    /// nothing levelled.
    let characterExperience: Float
    /// What banking that experience did to the character level, or nil when the
    /// session runs no character leveling (issue #499).
    let levelUp: PlayerLevelUpReport?

    init(
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

    var levelsGained: Int {
        Int(level - previousLevel)
    }

    var didAdvance: Bool {
        level > previousLevel
    }
}

/// What skill advancement did and declined to do.
///
/// Shaped like `PerkRuntimeTally`: every gap is a counter rather than a log
/// line, so a sweep asserts a number and a panel prints one.
nonisolated struct SkillAdvancementTally: Equatable, Sendable {
    /// Uses converted into experience.
    private(set) var uses = 0
    /// Skill points gained.
    private(set) var advances = 0
    /// Uses dropped because the actor was not the player. Skills advance for
    /// the player only; an NPC's stay derived from its records.
    private(set) var nonPlayerUses = 0
    /// Uses dropped because no skill claims the action — an unarmed strike, a
    /// blow taken in no armour, an effect whose MGEF names no magic skill.
    private(set) var unclaimedUses = 0
    /// Uses dropped because this load order carries no AVIF advancement
    /// parameters for the skill, which is every synthetic session with no game
    /// data behind it.
    private(set) var missingParameters = 0
    /// Uses dropped because the amount was zero, negative or not finite.
    private(set) var emptyUses = 0
    /// Character levels gained by the points this runtime granted (issue #499).
    private(set) var characterLevels = 0

    var isClean: Bool {
        missingParameters == 0
    }

    mutating func noteUse() {
        uses += 1
    }

    mutating func noteAdvances(_ count: Int) {
        advances += max(0, count)
    }

    mutating func noteNonPlayer() {
        nonPlayerUses += 1
    }

    mutating func noteUnclaimed() {
        unclaimedUses += 1
    }

    mutating func noteMissingParameters() {
        missingParameters += 1
    }

    mutating func noteEmpty() {
        emptyUses += 1
    }

    mutating func noteCharacterLevels(_ count: Int) {
        characterLevels += max(0, count)
    }
}
