// What a skill level-up hands to character leveling (issue #498, roadmap item
// 20.5), and the counters that say what the runtime declined to do.
//
// ## Why this is a value the runtime holds rather than a stored component
//
// Item 20.5 owns one half of the exchange: a skill that goes up reports what
// the level-up is worth in character experience, by the formula UESP states
// ("Character XP gained = Skill level acquired * fXPPerSkillRank"). The other
// half — the character level curve, the attribute pick, the perk point, and
// where all of that persists — is item 20.6, and inventing a save chunk for it
// here would fix a shape that item has not decided yet.
//
// So this is a plain accumulator, exposed read-only, and a session that reloads
// starts it at zero. That gap is deliberate and is written down rather than
// hidden: the *skill* half of progression persists already, because accumulated
// skill experience lives in the `Skill Advance` actor values and travels in the
// save with every other actor value (docs/engine/skill-advancement.md).
//
// Documented in docs/engine/skill-advancement.md.

import Foundation

/// Character-level progress banked by skill level-ups this session.
nonisolated struct PlayerProgressState: Equatable, Sendable {
    /// Character experience earned, summed over every skill point gained.
    private(set) var bankedExperience: Float = 0
    /// How many skill points were gained, which is the number the level-up
    /// screen counts and the number a trainer's per-level cap is checked
    /// against (item 20.6).
    private(set) var skillIncreases = 0

    init(bankedExperience: Float = 0, skillIncreases: Int = 0) {
        self.bankedExperience = max(0, bankedExperience)
        self.skillIncreases = max(0, skillIncreases)
    }

    /// Banks one advance's contribution. A non-finite or negative amount banks
    /// nothing, by the rule every runtime here follows: a bad number is ignored
    /// rather than propagated.
    mutating func bank(_ outcome: SkillAdvanceOutcome) {
        guard outcome.levelsGained > 0 else { return }
        skillIncreases += outcome.levelsGained
        guard outcome.characterExperience.isFinite, outcome.characterExperience > 0 else {
            return
        }
        bankedExperience += outcome.characterExperience
    }
}

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
}
