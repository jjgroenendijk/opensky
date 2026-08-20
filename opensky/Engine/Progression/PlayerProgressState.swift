// The player's character-level progress, as a world-state component (issue
// #499, roadmap item 20.6).
//
// ## Why this is stored and the skill half is not
//
// Skill progress lives in the `Skill Advance` actor values, because the vanilla
// table already has a slot per skill holding exactly that quantity
// (docs/engine/skill-advancement.md). Nothing in that table holds a character
// level, banked character experience, or a count of unspent perk points, so
// this is the one part of progression that needs a component of its own. It is
// keyed by `ReferenceKey.player` and travels in the save's `PLVL` chunk.
//
// Item 20.5 left the character-experience contribution in a session accumulator
// with the shape of the persisted thing deliberately undecided; this is that
// shape, and the accumulator is gone.
//
// ## What is stored, and what is not
//
// Stored: the level, the experience banked toward the next one, the unspent
// perk-point pool, how many attribute picks are owed, and the history of picks
// already made.
//
// Not stored: the *effect* of a pick. Choosing health adds `iAVDhmsLevelUp`
// points to the health base through the item 20.3 base-override path, which is
// where every other session-made deviation from a derived baseline lives. Two
// homes for the same ten points would be two chances to disagree, and the
// override is the one the actor-value runtime already reads. The history is
// therefore a record of what happened rather than the mechanism — it is what a
// level-up screen lists and what a save inspector prints.
//
// The component is dropped once it says nothing, exactly as `PerkState` and
// `SpellbookState` are, so a session that never levels stays clean.
//
// Documented in docs/engine/character-leveling.md.

import Foundation

/// The player's level, banked character experience and perk-point pool.
nonisolated struct PlayerProgressState: WorldStateComponent {
    /// Most perk points the pool holds. The Creation Kit wiki states the cap on
    /// the function that writes it: "Final values can not exceed 255."
    /// (<https://ck.uesp.net/wiki/ModPerkPoints_-_Game>)
    static let maximumPerkPoints = 255

    /// The character level, which is what `GetLevel` reports for the player.
    private(set) var level: Int
    /// Character experience banked toward the next level, always below the next
    /// threshold once a level-up has been run against it.
    private(set) var experience: Float
    /// Perk points earned and not yet spent.
    private(set) var perkPoints: Int
    /// Attribute picks the player is owed and has not made — one per level
    /// gained. "if you gained 4 levels you will be prompted to make 4 choices
    /// in succession" (<https://en.uesp.net/wiki/Skyrim:Leveling>).
    private(set) var pendingAttributePicks: Int
    /// Every pick already made, oldest first.
    private(set) var attributePicks: [ActorValueKind]
    /// Skill points gained over the session, which is the number a level-up
    /// screen counts and a trainer's per-level cap is checked against.
    private(set) var skillIncreases: Int

    static var componentKind: WorldStateComponentKind {
        .playerProgress
    }

    var erased: WorldStateComponentValue {
        .playerProgress(self)
    }

    /// Normalizes on the way in, which is what makes this the save decoder's
    /// entry point: a file written by a different build, or corrupted, restores
    /// a component every reader can trust rather than a NaN that spreads.
    init(
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

    init?(erased: WorldStateComponentValue) {
        guard case let .playerProgress(value) = erased else { return nil }
        self = value
    }

    /// True when the component says nothing a fresh session would not, which is
    /// when the store drops the slot rather than keeping it around.
    var isEmpty: Bool {
        self == PlayerProgressState()
    }

    /// How many times each attribute has been picked, which is what a readout
    /// prints beside the three bars.
    func pickCount(of kind: ActorValueKind) -> Int {
        attributePicks.count { $0 == kind }
    }

    // MARK: - Deriving

    /// Banks `amount` toward the next level without spending it.
    ///
    /// A non-finite or negative amount banks nothing, by the rule every runtime
    /// here follows: a bad number is ignored rather than propagated.
    func banking(experience amount: Float) -> PlayerProgressState {
        guard amount.isFinite, amount > 0 else { return self }
        return with { $0.experience += amount }
    }

    /// Records `levels` gained and the experience left carrying, granting one
    /// perk point and one owed attribute pick per level.
    func leveled(_ outcome: CharacterLevelOutcome) -> PlayerProgressState {
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
    func choosing(_ kind: ActorValueKind) -> PlayerProgressState? {
        guard pendingAttributePicks > 0 else { return nil }
        return with {
            $0.pendingAttributePicks -= 1
            $0.attributePicks.append(kind)
        }
    }

    /// Takes one perk point out of the pool.
    ///
    /// - Returns: nil when the pool is empty.
    func spendingPerkPoint() -> PlayerProgressState? {
        guard perkPoints > 0 else { return nil }
        return with { $0.perkPoints -= 1 }
    }

    /// Adds `delta` perk points, clamped to the pool's documented bounds. The
    /// write behind `Game.ModPerkPoints`.
    func modifyingPerkPoints(by delta: Int) -> PlayerProgressState {
        with { $0.perkPoints = min(Self.maximumPerkPoints, max(0, $0.perkPoints + delta)) }
    }

    /// Notes `count` skill points gained.
    func notingSkillIncreases(_ count: Int) -> PlayerProgressState {
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
