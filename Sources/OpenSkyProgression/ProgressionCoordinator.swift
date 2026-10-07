// The shell of skill advancement and character leveling: owns both runtimes,
// receives every skill use, and runs the two player-facing spends, the
// attribute pick and the perk point. See docs/engine/coordinators.md,
// docs/engine/skill-advancement.md and docs/engine/character-leveling.md.

import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgressionInterface

/// Owns skill advancement and leveling, and reads the world through
/// `ProgressionWorld`. Without game data both runtimes stay nil: every skill
/// use is dropped and nothing levels.
@MainActor
public final class ProgressionCoordinator {
    public let perks: PerkCoordinator
    /// Nil until `wireSkills`.
    public private(set) var skills: SkillAdvancementRuntime?
    public private(set) var lastAdvance: SkillAdvanceReport?
    /// Nil until `wireLeveling`.
    public private(set) var leveling: PlayerLevelRuntime?
    /// Where each perk sits in a skill's tree. Empty without game data, and
    /// every spend is then refused with `.notInPerkTree`.
    public private(set) var trees = PerkTreeIndex.empty
    /// The AVIF index the panel browses a skill's perk tree out of.
    public private(set) var information: ActorValueInformationStore?
    /// The panel asks twice a second; walking eighteen trees each time is
    /// about nine hundred record lookups for numbers that rarely move.
    var treeCounts = PerkTreeCountCache()
    /// By vanilla actor-value index. Change it with `selectSkill(_:)`.
    public private(set) var skillSelection = ActorValueIdentity.firstSkillIndex
    /// The selected box of that skill's tree, by `INAM`.
    public var nodeSelection: UInt32 = 0
    public internal(set) var lastActionText = "No leveling action yet."

    weak var world: (any ProgressionWorld)?
    /// Takes `SKIL` and `LEVL`.
    public weak var storyEvents: (any StoryEventReporting)?

    public init(perks: PerkCoordinator) {
        self.perks = perks
    }

    public func attach(world: any ProgressionWorld) {
        self.world = world
    }

    public func wireSkills(
        values: any ActorValueAccess,
        information: ActorValueInformationStore,
        settings: SkillAdvancementSettings = .documentedDefaults
    ) {
        var runtime = SkillAdvancementRuntime(
            values: values,
            parameters: SkillUseParameterSource(store: information),
            settings: settings
        )
        runtime.wornArmor = { [weak self] key in self?.world?.wornArmor(of: key) ?? .none }
        runtime.leveling = leveling
        skills = runtime
    }

    /// After `wireSkills`: the skill runtime banks into this one.
    public func wireLeveling(
        values: any ActorValueAccess,
        settings: CharacterLevelSettings = .documentedDefaults,
        perkStore: PerkStore?,
        information: ActorValueInformationStore?
    ) {
        let leveling = PlayerLevelRuntime(values: values, settings: settings)
        self.leveling = leveling
        if let perkStore, let information {
            trees = PerkTreeIndex(information: information, perks: perkStore)
            self.information = information
            // Counts taken against the old stores describe records that are gone.
            treeCounts.invalidate()
            nodeSelection = firstNode(forSkill: skillSelection)
        }
        skills?.leveling = leveling
    }

    /// Ignores an index that is not a skill. The old box means nothing in the
    /// new tree, so the box lands on the new tree's first one.
    public func selectSkill(_ index: Int32) {
        guard ActorValueIdentity.isSkill(index: index), index != skillSelection else { return }
        skillSelection = index
        nodeSelection = firstNode(forSkill: index)
    }

    // MARK: - Skills

    /// Blows, arrows and casts all report here.
    ///
    /// - Returns: the skill experience awarded; zero for an NPC, for an action
    ///   no skill claims, and without progression data.
    @discardableResult
    public func reportSkillUse(_ use: SkillUseEvent) -> Float {
        guard var runtime = skills else { return 0 }
        let report = runtime.record(use)
        store(runtime, report: report)
        return report?.experience ?? 0
    }

    /// `Game.AdvanceSkill`. Returns whether the skill took it.
    @discardableResult
    public func advanceSkill(_ index: Int32, byUse magnitude: Float) -> Bool {
        guard var runtime = skills else { return false }
        let report = runtime.advance(skill: index, byUse: magnitude, on: runtime.player)
        store(runtime, report: report)
        return report != nil
    }

    /// `Game.IncrementSkill`. Returns whether the skill took it.
    @discardableResult
    public func incrementSkill(_ index: Int32) -> Bool {
        guard var runtime = skills else { return false }
        let report = runtime.increment(skill: index, on: runtime.player)
        store(runtime, report: report)
        return report != nil
    }

    // MARK: - Spending

    @discardableResult
    public func chooseAttribute(_ kind: ActorValueKind) -> PlayerProgressResult {
        guard let leveling else { return .failure(.noAttributePickOwed) }
        return leveling.chooseAttribute(kind)
    }

    /// The point is taken after the grant, so a failed grant cannot leave the
    /// player a point short. The grant applies the perk's abilities.
    @discardableResult
    public func spendPerkPoint(on perk: ReferenceKey) -> PlayerProgressResult {
        guard let leveling, perks.runtime != nil else { return .failure(.noPerkPoints) }
        guard leveling.perkPoints > 0 else { return .failure(.noPerkPoints) }
        if let refusal = spendRefusal(for: perk, on: leveling.holder) {
            return .failure(.perkRefused(refusal))
        }
        guard perks.add(perk, to: leveling.holder) else {
            return .failure(.perkRefused(.alreadyOwned))
        }
        return leveling.spendPerkPoint()
    }

    /// Nil when the player can buy `perk` now.
    public func perkSpendRefusal(for perk: ReferenceKey) -> PerkSpendRefusal? {
        spendRefusal(for: perk, on: .player)
    }

    /// `Game.ModPerkPoints`. A zero delta is the read behind `Game.GetPerkPoints`.
    ///
    /// - Returns: the pool afterwards, or nil without leveling.
    public func modifyPerkPoints(by delta: Int) -> Int? {
        leveling?.modifyPerkPoints(by: delta).perkPoints
    }

    private func spendRefusal(
        for perk: ReferenceKey,
        on holder: ActorValueHolder
    ) -> PerkSpendRefusal? {
        guard let runtime = perks.runtime else { return .unresolvedPerk }
        let validator = PerkTreeSpendValidator(
            runtime: runtime, trees: trees, conditionRegistry: runtime.conditionRegistry
        )
        return validator.refusal(
            for: perk, on: holder, conditions: world?.conditionContext() ?? ConditionContext()
        )
    }

    private func store(_ runtime: SkillAdvancementRuntime, report: SkillAdvanceReport?) {
        skills = runtime
        guard let report else { return }
        lastAdvance = report
        if report.didAdvance {
            storyEvents?.reportStoryEvent(.skillIncrease(skill: report.skill))
        }
        if let levelUp = report.levelUp {
            reportLevel(levelUp)
        }
    }

    func reportLevel(_ report: PlayerLevelUpReport) {
        guard report.didLevel else { return }
        storyEvents?.reportStoryEvent(.levelIncrease(level: report.level))
    }
}

/// Crafting reports through the same method combat's adapters call.
extension ProgressionCoordinator: SkillUseReporting {}
