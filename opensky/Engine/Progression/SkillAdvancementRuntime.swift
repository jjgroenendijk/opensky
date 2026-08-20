// Turning skill use into skill level (issue #498, roadmap item 20.5): the layer
// that takes a `SkillUseEvent` from a combat or magic runtime, converts it with
// the skill's own AVIF parameters, banks it, and spends it on a level when it
// crosses the threshold.
//
// A thin layer beside `ActorValueRuntime`, following `PerkRuntime` and
// `SpellbookRuntime`. Every write goes through `ActorValueRuntime`, so a skill
// point and the experience under it land in the journal, the dirty counts and
// the save exactly like a sword's damage does.
//
// Headless and AppKit-free: this compiles into `openskycli` and is testable
// without a window. `@MainActor` only because the runtime it writes through is.
//
// Failure model: nothing here throws. A use no skill claims, a use by an NPC,
// and a load order with no AVIF parameters are each a counted drop rather than
// an error — a fight that stops because progression could not resolve a skill
// would be a far worse outcome than a fight that levels nothing.
//
// ## Where accumulated experience is stored, and why not in a component
//
// In the `Skill Advance` actor values — the eighteen slots at indices 114
// through 131 that the vanilla actor-value table names one per skill and that
// nothing else in the engine writes. A dedicated world-state component was the
// alternative and was rejected for three reasons:
//
// 1. The table already has exactly these slots and they hold exactly this
//    quantity. A component beside them would be a second place skill progress
//    lives, and the two could disagree.
// 2. `GetActorValue OneHandedSkillAdvance` is a question the game's own script
//    corpus and console can ask. Answering it from the same number the
//    progression runtime spends is free this way and impossible the other way
//    without a bridge.
// 3. Persistence, the journal and the save already carry actor values, so the
//    skill half of progression survives a reload with no new save chunk.
//
// The cost of the decision is that a script can write skill progress with
// `SetActorValue`, which vanilla also allows, so it is a shared behaviour
// rather than a hole.
//
// Documented in docs/engine/skill-advancement.md.

import Foundation

/// Where a skill's `AVSK` advancement parameters come from.
///
/// A lookup rather than the store itself, so a unit test can state a skill's
/// four numbers directly while a session reads the winning AVIF record for the
/// same index. Both forms answer the identical question, which is what makes
/// the synthetic suites and `SkillAdvancementRealDataTests` two views of one
/// code path rather than two code paths.
nonisolated struct SkillUseParameterSource {
    private let lookup: @Sendable (Int32) -> SkillUseParameters?

    init(lookup: @escaping @Sendable (Int32) -> SkillUseParameters?) {
        self.lookup = lookup
    }

    /// The load order's own answer: the winning AVIF record for the actor value
    /// index, and the `AVSK` field on it.
    init(store: ActorValueInformationStore) {
        var table: [Int32: SkillUseParameters] = [:]
        for index in ActorValueIdentity.skillIndices {
            guard let use = store.information(actorValueIndex: index)?.information.skillUse
            else { continue }
            table[index] = use
        }
        self.init(table: table)
    }

    /// A stated table, which is what a synthetic fixture hands over.
    init(table: [Int32: SkillUseParameters]) {
        self.init { table[$0] }
    }

    /// Nothing at all: every skill answers nil, which is a session with no game
    /// data and therefore no advancement.
    static let none = SkillUseParameterSource { _ in nil }

    func parameters(forSkill index: Int32) -> SkillUseParameters? {
        lookup(index)
    }
}

/// Converts skill use into skill level on top of an `ActorValueRuntime`.
@MainActor
struct SkillAdvancementRuntime {
    /// The read and write surface for both the skill and the slot holding its
    /// accumulated experience.
    let values: ActorValueRuntime
    /// Per-skill `AVSK` parameters.
    let parameters: SkillUseParameterSource
    /// The two resolved game settings.
    var settings: SkillAdvancementSettings
    /// What the actor taking a blow is wearing, which is the one thing a hit
    /// cannot say about itself. Answers `.none` in a session with no equipment
    /// resolution, and an armoured hit then credits nothing rather than
    /// guessing a skill.
    var wornArmor: @MainActor (ReferenceKey) -> WornArmorProfile = { _ in .none }
    /// Character leveling, which is what a skill point's banked experience is
    /// spent on (issue #499). Nil in a session with no character leveling, and
    /// the experience is then computed and reported but not banked anywhere —
    /// which is what every synthetic suite that drives skills alone does.
    var leveling: PlayerLevelRuntime?
    private(set) var tally = SkillAdvancementTally()

    /// The player's stored progress, or a fresh one when this session runs no
    /// character leveling.
    var progress: PlayerProgressState {
        leveling?.state ?? PlayerProgressState()
    }

    init(
        values: ActorValueRuntime,
        parameters: SkillUseParameterSource = .none,
        settings: SkillAdvancementSettings = .documentedDefaults
    ) {
        self.values = values
        self.parameters = parameters
        self.settings = settings
    }

    // MARK: - Reading

    /// The player's holder, which is the only character this runtime advances.
    var player: ActorValueHolder {
        .player
    }

    /// `skill`'s current base level — what the records author plus whatever
    /// training and level-ups have added, and never a Fortify modifier: a
    /// fortified skill is not a trained one, and letting a potion move the
    /// threshold would make advancement depend on what the character drank.
    func level(ofSkill index: Int32, on holder: ActorValueHolder) -> Float {
        values.baseValue(at: index, on: holder) ?? ActorValueIdentity.skillFloor
    }

    /// Experience accumulated toward `skill`'s next level, read out of the
    /// skill's `Skill Advance` slot. Zero for a skill nothing has used, and the
    /// read the progression panel of item 20.7 takes.
    func experience(forSkill index: Int32, on holder: ActorValueHolder) -> Float {
        guard let slot = ActorValueIdentity.skillAdvanceIndex(forSkill: index) else { return 0 }
        return max(0, values.baseValue(at: slot, on: holder) ?? 0)
    }

    /// What `skill` needs to reach its next level from where it stands, or zero
    /// when this load order carries no parameters for it.
    func threshold(forSkill index: Int32, on holder: ActorValueHolder) -> Float {
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
    mutating func record(_ use: SkillUseEvent) -> SkillAdvanceReport? {
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

    /// Advances one skill by a use amount, which is `Game.AdvanceSkill`'s own
    /// unit: "The amount by which the skill progress will be advanced. This is
    /// in Skill Usage amounts, so it will count towards skill progression but
    /// won't necessarily change the Skill itself"
    /// (<https://ck.uesp.net/wiki/AdvanceSkill_-_Game>).
    ///
    /// - Returns: nil for an index that is not one of the eighteen skills, and
    ///   for a load order carrying no parameters for it.
    @discardableResult
    mutating func advance(
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

    /// Raises one skill by a whole point, which is `Game.IncrementSkill`:
    /// "Advances the provided Skill by the one point (for the player only)"
    /// (<https://ck.uesp.net/wiki/IncrementSkill_-_Game>).
    ///
    /// The accumulated experience is left exactly where it was. The point did
    /// not come from use — a trainer, a skill book, a quest reward — so
    /// spending the progress the character earned by using the skill would take
    /// away something the point did not pay for. The character experience is
    /// banked, because the level was still acquired.
    ///
    /// - Returns: nil for an index that is not a skill, and for a skill already
    ///   at the ceiling, which cannot take the point.
    @discardableResult
    mutating func increment(
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
