// Turns a `SkillUseEvent` into skill levels with the skill's AVIF parameters.
// Every write goes through `ActorValueRuntime`. Nothing throws: an unclaimed use is
// a counted drop. Experience lives in the `Skill Advance` actor values (114-131),
// not a component: the slots exist, scripts can read them, and the save already
// carries them. See docs/engine/skill-advancement.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgressionInterface

/// Where a skill's `AVSK` parameters come from. A lookup, so a unit test states
/// the four numbers while a session reads the AVIF record, through one code path.
nonisolated public struct SkillUseParameterSource: Sendable {
    private let lookup: @Sendable (Int32) -> SkillUseParameters?

    public init(lookup: @escaping @Sendable (Int32) -> SkillUseParameters?) {
        self.lookup = lookup
    }

    /// The load order's own answer: the winning AVIF record for the actor value
    /// index, and the `AVSK` field on it.
    public init(store: ActorValueInformationStore) {
        var table: [Int32: SkillUseParameters] = [:]
        for index in ActorValueIdentity.skillIndices {
            guard let use = store.information(actorValueIndex: index)?.information.skillUse
            else { continue }
            table[index] = use
        }
        self.init(table: table)
    }

    /// A stated table, which is what a synthetic fixture hands over.
    public init(table: [Int32: SkillUseParameters]) {
        self.init { table[$0] }
    }

    /// Nothing at all: every skill answers nil, which is a session with no game
    /// data and therefore no advancement.
    public static let none = SkillUseParameterSource { _ in nil }

    public func parameters(forSkill index: Int32) -> SkillUseParameters? {
        lookup(index)
    }
}

/// Converts skill use into skill level on top of an `ActorValueRuntime`.
@MainActor
public struct SkillAdvancementRuntime {
    /// The read and write surface for both the skill and the slot holding its
    /// accumulated experience.
    public let values: any ActorValueAccess
    /// Per-skill `AVSK` parameters.
    public let parameters: SkillUseParameterSource
    /// The two resolved game settings.
    public var settings: SkillAdvancementSettings
    /// What the actor taking a blow is wearing, which is the one thing a hit
    /// cannot say about itself. Answers `.none` in a session with no equipment
    /// resolution, and an armoured hit then credits nothing rather than
    /// guessing a skill.
    public var wornArmor: @MainActor (ReferenceKey) -> WornArmorProfile = { _ in .none }
    /// Character leveling, where banked experience is spent. Nil in a session
    /// without leveling: experience is then reported but not banked.
    public var leveling: PlayerLevelRuntime?
    public private(set) var tally = SkillAdvancementTally()

    /// The player's stored progress, or a fresh one when this session runs no
    /// character leveling.
    public var progress: PlayerProgressState {
        leveling?.state ?? PlayerProgressState()
    }

    public init(
        values: any ActorValueAccess,
        parameters: SkillUseParameterSource = .none,
        settings: SkillAdvancementSettings = .documentedDefaults
    ) {
        self.values = values
        self.parameters = parameters
        self.settings = settings
    }

    // MARK: - Reading

    /// The player's holder, which is the only character this runtime advances.
    public var player: ActorValueHolder {
        .player
    }

    /// `skill`'s current base level — what the records author plus whatever
    /// training and level-ups have added, and never a Fortify modifier: a
    /// fortified skill is not a trained one, and letting a potion move the
    /// threshold would make advancement depend on what the character drank.
    public func level(ofSkill index: Int32, on holder: ActorValueHolder) -> Float {
        values.baseValue(at: index, on: holder) ?? ActorValueIdentity.skillFloor
    }

    /// Experience toward `skill`'s next level, from its `Skill Advance` slot. Zero for an
    /// unused skill. The progression panel reads it.
    public func experience(forSkill index: Int32, on holder: ActorValueHolder) -> Float {
        guard let slot = ActorValueIdentity.skillAdvanceIndex(forSkill: index) else { return 0 }
        return max(0, values.baseValue(at: slot, on: holder) ?? 0)
    }

    /// What `skill` needs to reach its next level from where it stands, or zero
    /// when this load order carries no parameters for it.
    public func threshold(forSkill index: Int32, on holder: ActorValueHolder) -> Float {
        guard let use = parameters.parameters(forSkill: index) else { return 0 }
        return SkillAdvancement.threshold(
            atSkillLevel: level(ofSkill: index, on: holder),
            parameters: use,
            settings: settings
        )
    }

    // MARK: - Recording use

    /// Converts one reported use into experience on the player's skill.
    ///
    /// - Returns: what the use did, or nil when it was dropped — an NPC's
    ///   action, an action no skill claims, an empty amount, or a load order
    ///   with no advancement parameters for the skill. Every one of those is
    ///   counted in the tally.
    @discardableResult
    public mutating func record(_ use: SkillUseEvent) -> SkillAdvanceReport? {
        guard use.actor == ReferenceKey.player else {
            tally.noteNonPlayer()
            return nil
        }
        guard use.amount.isFinite, use.amount > 0 else {
            tally.noteEmpty()
            return nil
        }
        guard let credited = credit(for: use) else {
            tally.noteUnclaimed()
            return nil
        }
        return advance(skill: credited.skill, byUse: credited.amount, on: player)
    }

    /// Advances one skill by a use amount, `Game.AdvanceSkill`'s unit
    /// (<https://ck.uesp.net/wiki/AdvanceSkill_-_Game>). Returns nil for a non-skill
    /// index or a load order without its parameters.
    @discardableResult
    public mutating func advance(
        skill index: Int32,
        byUse amount: Float,
        on holder: ActorValueHolder
    ) -> SkillAdvanceReport? {
        guard
            ActorValueIdentity.isSkill(index: index),
            let slot = ActorValueIdentity.skillAdvanceIndex(forSkill: index)
        else { return nil }
        guard let use = parameters.parameters(forSkill: index) else {
            tally.noteMissingParameters()
            return nil
        }
        tally.noteUse()
        let gained = SkillAdvancement.experience(forUse: amount, parameters: use)
        let previous = level(ofSkill: index, on: holder)
        let outcome = SkillAdvancement.advance(
            experience: experience(forSkill: index, on: holder) + gained,
            from: previous,
            parameters: use,
            settings: settings
        )
        values.setBase(at: slot, to: outcome.carriedExperience, on: holder)
        var levelUp: PlayerLevelUpReport?
        if outcome.levelsGained > 0 {
            values.advanceSkill(at: index, by: Float(outcome.levelsGained), on: holder)
            tally.noteAdvances(outcome.levelsGained)
            levelUp = bank(outcome)
        }
        return SkillAdvanceReport(
            skill: index,
            experience: gained,
            previousLevel: previous,
            level: outcome.level,
            carriedExperience: outcome.carriedExperience,
            characterExperience: outcome.characterExperience,
            levelUp: levelUp
        )
    }

    /// Raises one skill by a point, as `Game.IncrementSkill` does. Skill progress
    /// stays, because the point did not come from use; character experience is
    /// banked. Returns nil for a non-skill index or a skill at the ceiling.
    @discardableResult
    public mutating func increment(
        skill index: Int32,
        on holder: ActorValueHolder
    ) -> SkillAdvanceReport? {
        guard ActorValueIdentity.isSkill(index: index) else { return nil }
        let previous = level(ofSkill: index, on: holder)
        guard previous < SkillAdvancement.skillCeiling else { return nil }
        let level = min(previous + 1, SkillAdvancement.skillCeiling)
        values.advanceSkill(at: index, by: level - previous, on: holder)
        let banked = SkillAdvancement.characterExperience(forSkillLevel: level, settings: settings)
        let outcome = SkillAdvanceOutcome(
            levelsGained: 1,
            level: level,
            carriedExperience: experience(forSkill: index, on: holder),
            characterExperience: banked
        )
        tally.noteAdvances(1)
        let levelUp = bank(outcome)
        return SkillAdvanceReport(
            skill: index,
            experience: 0,
            previousLevel: previous,
            level: level,
            carriedExperience: outcome.carriedExperience,
            characterExperience: banked,
            levelUp: levelUp
        )
    }

    // MARK: - Private

    /// Hands one advance's character experience to the level runtime and counts
    /// whatever levels it bought.
    ///
    /// - Returns: nil when this session runs no character leveling, which is a
    ///   gap in the wiring rather than a refusal: the skill still went up, and
    ///   the experience it banked has nowhere to go.
    private mutating func bank(_ outcome: SkillAdvanceOutcome) -> PlayerLevelUpReport? {
        guard let leveling else { return nil }
        leveling.noteSkillIncreases(outcome.levelsGained)
        let report = leveling.award(characterExperience: outcome.characterExperience)
        tally.noteCharacterLevels(report.levelsGained)
        return report
    }

    /// Which skill a use credits and with how much base experience, resolving
    /// the one action that needs the world to answer.
    private func credit(for use: SkillUseEvent) -> (skill: Int32, amount: Float)? {
        if case .armorHit = use.action {
            guard let worn = wornArmor(use.actor).creditedSkill else { return nil }
            return (worn.index, use.amount * Float(worn.pieces))
        }
        guard let skill = use.action.skillIndex else { return nil }
        return (skill, use.amount)
    }
}
