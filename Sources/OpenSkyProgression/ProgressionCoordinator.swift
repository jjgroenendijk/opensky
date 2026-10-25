// The shell of skill advancement and character leveling: owns both runtimes,
// receives every skill use, and runs the two player-facing spends, the
// attribute pick and the perk point. See docs/engine/coordinators.md,
// docs/engine/skill-advancement.md and docs/engine/character-leveling.md.

import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgressionInterface

/// The load order's progression data. Without the AVIF index no skill
/// advances and no perk tree exists, but the player still levels.
public struct ProgressionSessionData {
    public let values: any ActorValueAccess
    public let information: ActorValueInformationStore?
    public let perkStore: PerkStore?
    public let skillSettings: SkillAdvancementSettings
    public let levelSettings: CharacterLevelSettings
    public let training: TrainingSettings
    public let texts: ProgressionTexts

    public init(
        values: any ActorValueAccess,
        information: ActorValueInformationStore?,
        perkStore: PerkStore?,
        skillSettings: SkillAdvancementSettings = .documentedDefaults,
        levelSettings: CharacterLevelSettings = .documentedDefaults,
        training: TrainingSettings = .vanilla,
        texts: ProgressionTexts = .vanilla
    ) {
        self.values = values
        self.information = information
        self.perkStore = perkStore
        self.skillSettings = skillSettings
        self.levelSettings = levelSettings
        self.training = training
        self.texts = texts
    }
}

/// Owns skill advancement and leveling, and reads the world through
/// `ProgressionWorld`. Without game data both runtimes stay nil: every skill
/// use is dropped and nothing levels.
@MainActor
public final class ProgressionCoordinator {
    public let perks: PerkCoordinator
    /// Nil without actor values or the AVIF index.
    public private(set) var skills: SkillAdvancementRuntime?
    /// Nil without actor values.
    public let leveling: PlayerLevelRuntime?
    /// Where each perk sits in a skill's tree. Empty without game data, and
    /// every spend is then refused with `.notInPerkTree`.
    public let trees: PerkTreeIndex
    /// The AVIF index the readout browses a skill's perk tree out of.
    public let information: ActorValueInformationStore?
    /// The readout asks twice a second; walking eighteen trees each time is
    /// about nine hundred record lookups for numbers that rarely move.
    var treeCounts = PerkTreeCountCache()
    /// By vanilla actor-value index. Change it with `selectSkill(_:)`.
    public private(set) var skillSelection = ActorValueIdentity.firstSkillIndex
    /// The selected box of that skill's tree, by `INAM`.
    public var nodeSelection: UInt32 = 0
    public internal(set) var lastAction = ProgressionActionOutcome.idle
    /// Cost, per-level cap, and refusal notices.
    public let training: TrainingSettings
    public let texts: ProgressionTexts

    let world: any ProgressionWorld
    var pendingCommands: [ProgressionCommand] = []
    /// Earned levels the HUD has announced, so each shows its notice once.
    var announcedLevelsReady = 0
    private var cachedStrings: LocalizedStrings??
    /// Takes `SKIL` and `LEVL`.
    public weak let storyEvents: (any StoryEventReporting)?

    /// Builds the skill runtime over the leveling runtime, so a skill use banks
    /// into it from the first call.
    public init(
        perks: PerkCoordinator,
        world: any ProgressionWorld,
        data: ProgressionSessionData?,
        storyEvents: (any StoryEventReporting)? = nil
    ) {
        self.perks = perks
        self.world = world
        self.storyEvents = storyEvents
        training = data?.training ?? .vanilla
        texts = data?.texts ?? .vanilla
        let leveling = data.map {
            PlayerLevelRuntime(values: $0.values, settings: $0.levelSettings)
        }
        self.leveling = leveling
        if leveling != nil, let perkStore = data?.perkStore, let information = data?.information {
            trees = PerkTreeIndex(information: information, perks: perkStore)
            self.information = information
        } else {
            trees = .empty
            information = nil
        }
        guard let data, let information = data.information else { return }
        var runtime = SkillAdvancementRuntime(
            values: data.values,
            parameters: SkillUseParameterSource(store: information),
            settings: data.skillSettings
        )
        runtime.wornArmor = { [weak self] key in self?.world.wornArmor(of: key) ?? .none }
        runtime.useMultiplier = { [weak self] usage in self?.perks.skillUseMultiplier(usage) ?? 1 }
        runtime.leveling = leveling
        skills = runtime
        nodeSelection = firstNode(forSkill: skillSelection)
    }

    /// Notices and stats raised since the last call; the app runs them once a frame.
    public func takeCommands() -> [ProgressionCommand] {
        defer { pendingCommands = [] }
        return pendingCommands
    }

    /// Loaded on first use, because loading reads every table file.
    var strings: LocalizedStrings? {
        if let cachedStrings {
            return cachedStrings
        }
        let loaded = world.localizedStrings()
        cachedStrings = .some(loaded)
        return loaded
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

    /// A won Persuade, Intimidate, or Bribe: "75 * Speech level base XP for passing
    /// Speech checks" (UESP "Skyrim:Leveling"), read as the player's base Speech.
    @discardableResult
    public func reportSpeechCheckWon() -> Float {
        guard let skills, let speech = ActorValueIdentity.index(named: "Speech") else { return 0 }
        let level = skills.level(ofSkill: speech, on: skills.player)
        return reportSkillUse(SkillUseEvent(
            actor: .player, action: .speechCheck, amount: Self.speechCheckUse * level
        ))
    }

    static let speechCheckUse: Float = 75

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

    /// A served sentence: the skills nearest their next level lose their progress.
    /// - Returns: the skills that lost progress.
    @discardableResult
    public func loseJailProgress(days: Int, maximumDays: Int) -> [Int32] {
        guard let runtime = skills else { return [] }
        let count = SkillAdvancementRuntime.jailSkillCount(days: days, maximumDays: maximumDays)
        return runtime.clearProgress(ofSkills: count, on: runtime.player)
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
            for: perk, on: holder, conditions: world.conditionContext()
        )
    }

    func store(_ runtime: SkillAdvancementRuntime, report: SkillAdvanceReport?) {
        skills = runtime
        guard let report else { return }
        if report.didAdvance {
            storyEvents?.reportStoryEvent(.skillIncrease(skill: report.skill))
            pendingCommands.append(.showNotification(
                texts.skillIncreasedText(skill: skillName(report.skill), level: Int(report.level))
            ))
        }
        if let levelUp = report.levelUp {
            reportLevel(levelUp)
        }
    }

    /// The level-up notice shows once per level earned, not once per skill point
    /// banked while the level waits.
    func reportLevel(_ report: PlayerLevelUpReport) {
        if report.didLevel {
            storyEvents?.reportStoryEvent(.levelIncrease(level: report.level))
        }
        if report.levelsReady > announcedLevelsReady {
            pendingCommands.append(.showNotification(texts.levelUpAvailable))
        }
        announcedLevelsReady = report.levelsReady
    }

    /// Applies the levels banked experience has earned. The skills menu calls it as it
    /// opens, which is when the game raises the level. Nil without leveling.
    @discardableResult
    public func applyEarnedLevels() -> PlayerLevelUpReport? {
        guard let leveling else { return nil }
        let report = leveling.applyEarnedLevels()
        skills?.noteCharacterLevels(report.levelsGained)
        reportLevel(report)
        return report
    }
}

/// Crafting reports through the same method combat's adapters call.
extension ProgressionCoordinator: SkillUseReporting {}
