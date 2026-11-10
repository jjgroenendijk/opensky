// What skill advancement did and declined to do: the per-advance report and the
// session-wide tally. See docs/engine/skill-advancement.md.

import Foundation
import OpenSkyProgressionInterface

/// What skill advancement did and declined to do.
///
/// Shaped like `PerkRuntimeTally`: every gap is a counter rather than a log
/// line, so a sweep asserts a number and a readout prints one.
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
    /// Character levels gained by the points this runtime granted.
    public private(set) var characterLevels = 0

    var isClean: Bool {
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
