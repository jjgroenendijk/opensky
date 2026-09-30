// The player's character-level progress, as a world-state component keyed by
// `ReferenceKey.player`, saved in `PLVL`. It stores the level, banked
// experience, unspent perk points, owed attribute picks, and the pick history.
// A pick's effect lives in the actor-value base override, not here. Dropped
// once empty. See docs/engine/character-leveling.md.

import Foundation
import OpenSkyGameData
import OpenSkyWorldState

/// The player's level, banked character experience and perk-point pool.
nonisolated public struct PlayerProgressState: WorldStateComponent, Sendable {
    /// Most perk points the pool holds. The Creation Kit wiki states the cap on
    /// the function that writes it: "Final values can not exceed 255."
    /// (<https://ck.uesp.net/wiki/ModPerkPoints_-_Game>)
    public static let maximumPerkPoints = 255

    /// The character level, which is what `GetLevel` reports for the player.
    public private(set) var level: Int
    /// Character experience banked toward the next level, always below the next
    /// threshold once a level-up has been run against it.
    public private(set) var experience: Float
    /// Perk points earned and not yet spent.
    public private(set) var perkPoints: Int
    /// Attribute picks the player is owed and has not made — one per level
    /// gained. "if you gained 4 levels you will be prompted to make 4 choices
    /// in succession" (<https://en.uesp.net/wiki/Skyrim:Leveling>).
    public private(set) var pendingAttributePicks: Int
    /// Every pick already made, oldest first.
    public private(set) var attributePicks: [ActorValueKind]
    /// Skill points gained over the session, which is the number a level-up
    /// screen counts and a trainer's per-level cap is checked against.
    public private(set) var skillIncreases: Int

    public static var componentKind: WorldStateComponentKind {
        .playerProgress
    }

    /// Normalizes on the way in, which is what makes this the save decoder's
    /// entry point: a file written by a different build, or corrupted, restores
    /// a component every reader can trust rather than a NaN that spreads.
    public init(
        level: Int = PlayerLevelSource.startingLevel,
        experience: Float = 0,
        perkPoints: Int = 0,
        pendingAttributePicks: Int = 0,
        attributePicks: [ActorValueKind] = [],
        skillIncreases: Int = 0
    ) {
        self.level = max(PlayerLevelSource.startingLevel, level)
        self.experience = experience.isFinite ? max(0, experience) : 0
        self.perkPoints = min(Self.maximumPerkPoints, max(0, perkPoints))
        self.pendingAttributePicks = max(0, pendingAttributePicks)
        self.attributePicks = attributePicks
        self.skillIncreases = max(0, skillIncreases)
    }

    /// True when the component says nothing a fresh session would not, which is
    /// when the store drops the slot rather than keeping it around.
    public var isEmpty: Bool {
        self == PlayerProgressState()
    }

    /// How many times each attribute has been picked, which is what a readout
    /// prints beside the three bars.
    public func pickCount(of kind: ActorValueKind) -> Int {
        attributePicks.count { $0 == kind }
    }

    // MARK: - Deriving

    /// Banks `amount` toward the next level without spending it.
    ///
    /// A non-finite or negative amount banks nothing, by the rule every runtime
    /// here follows: a bad number is ignored rather than propagated.
    public func banking(experience amount: Float) -> PlayerProgressState {
        guard amount.isFinite, amount > 0 else { return self }
        return with { $0.experience += amount }
    }

    /// Records `levels` gained and the experience left carrying, granting one
    /// perk point and one owed attribute pick per level.
    public func leveled(_ outcome: CharacterLevelOutcome) -> PlayerProgressState {
        guard outcome.levelsGained > 0 else {
            return with { $0.experience = max(0, outcome.carriedExperience) }
        }
        return with {
            $0.level = outcome.level
            $0.experience = max(0, outcome.carriedExperience)
            $0.perkPoints = min(Self.maximumPerkPoints, $0.perkPoints + outcome.levelsGained)
            $0.pendingAttributePicks += outcome.levelsGained
        }
    }

    /// Consumes one owed attribute pick and records what was chosen.
    ///
    /// - Returns: nil when nothing is owed, which is the caller's cue to refuse
    ///   rather than hand out a free ten points.
    public func choosing(_ kind: ActorValueKind) -> PlayerProgressState? {
        guard pendingAttributePicks > 0 else { return nil }
        return with {
            $0.pendingAttributePicks -= 1
            $0.attributePicks.append(kind)
        }
    }

    /// Takes one perk point out of the pool.
    ///
    /// - Returns: nil when the pool is empty.
    public func spendingPerkPoint() -> PlayerProgressState? {
        guard perkPoints > 0 else { return nil }
        return with { $0.perkPoints -= 1 }
    }

    /// Adds `delta` perk points, clamped to the pool's documented bounds. The
    /// write behind `Game.ModPerkPoints`.
    public func modifyingPerkPoints(by delta: Int) -> PlayerProgressState {
        with { $0.perkPoints = min(Self.maximumPerkPoints, max(0, $0.perkPoints + delta)) }
    }

    /// Notes `count` skill points gained.
    public func notingSkillIncreases(_ count: Int) -> PlayerProgressState {
        guard count > 0 else { return self }
        return with { $0.skillIncreases += count }
    }

    private func with(
        _ change: (inout PlayerProgressState) -> Void
    ) -> PlayerProgressState {
        var copy = self
        change(&copy)
        return copy
    }
}

nonisolated extension WorldStateComponentKind {
    /// The player's character level, banked character experience, unspent perk
    /// points and attribute-pick history. Like `quest` it modifies no placement and
    /// belongs to no cell: it is keyed by `ReferenceKey.player`, who has no record
    /// in this engine. A slot of its own beside `perks` because the two answer
    /// different questions — how many points are left to spend, and which perks
    /// those points already bought.
    public static let playerProgress = Self(rawValue: "playerProgress", order: 18)
}
