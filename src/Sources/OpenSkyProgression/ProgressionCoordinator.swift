// The shell of skill advancement and character leveling: owns both runtimes,
// receives every skill use, and runs the two player-facing spends, the
// attribute pick and the perk point. See docs/engine/coordinators.md,
// docs/engine/skill-advancement.md and docs/engine/character-leveling.md.

public import OpenSkyActorsInterface
public import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyProgressionInterface

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
    let treeReader: ProgressionTreeReader
    /// By vanilla actor-value index. Change it with `selectSkill(_:)`.
    public private(set) var skillSelection = ActorValueIdentity.firstSkillIndex
    /// The selected box of that skill's tree, by `INAM`.
    public var nodeSelection: UInt32 = 0
    var lastAction = ProgressionActionOutcome.idle
    /// Cost, per-level cap, and refusal notices.
    public let training: TrainingSettings

    let world: any ProgressionWorld
    let notices: ProgressionNotices

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
        training = data?.training ?? .vanilla
        notices = ProgressionNotices(texts: data?.texts ?? .vanilla, storyEvents: storyEvents)
        let leveling = data.map {
            PlayerLevelRuntime(values: $0.values, settings: $0.levelSettings)
        }
        self.leveling = leveling
        treeReader = ProgressionTreeReader(
            perks: perks, world: world,
            data: leveling == nil ? nil : data.flatMap { data in
                data.information.flatMap { information in
                    data.perkStore.map { (information, $0) }
                }
            },
            texts: data?.texts ?? .vanilla
        )
        guard let data, let information = data.information else { return }
        var runtime = SkillAdvancementRuntime(data, information: information)
        runtime.wornArmor = { [weak self] key in self?.world.wornArmor(of: key) ?? .none }
        runtime.useMultiplier = { [weak self] usage in self?.perks.skillUseMultiplier(usage) ?? 1 }
        runtime.leveling = leveling
        skills = runtime
        nodeSelection = treeReader.firstNode(forSkill: skillSelection)
    }

    /// Notices and stats raised since the last call; the app runs them once a frame.
    public func takeCommands() -> [ProgressionCommand] {
        notices.take()
    }

    /// Falls back to the vanilla table, so a line always names something.
    func skillName(_ index: Int32) -> String {
        treeReader.skillName(index)
    }

    /// Ignores an index that is not a skill. The old box means nothing in the
    /// new tree, so the box lands on the new tree's first one.
    func selectSkill(_ index: Int32) {
        guard ActorValueIdentity.isSkill(index: index), index != skillSelection else { return }
        skillSelection = index
        nodeSelection = treeReader.firstNode(forSkill: index)
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
        return reportSkillUse(.speechCheckWon(speech: level))
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
        guard
            let leveling, perks.runtime != nil,
            leveling.perkPoints > 0 else { return .failure(.noPerkPoints) }
        if let refusal = treeReader.spendRefusal(for: perk, on: leveling.holder) {
            return .failure(.perkRefused(refusal))
        }
        guard perks.add(perk, to: leveling.holder) else {
            return .failure(.perkRefused(.alreadyOwned))
        }
        return leveling.spendPerkPoint()
    }

    /// `Game.ModPerkPoints`. A zero delta is the read behind `Game.GetPerkPoints`.
    ///
    /// - Returns: the pool afterwards, or nil without leveling.
    public func modifyPerkPoints(by delta: Int) -> Int? {
        leveling?.modifyPerkPoints(by: delta).perkPoints
    }

    func store(_ runtime: SkillAdvancementRuntime, report: SkillAdvanceReport?) {
        skills = runtime
        guard let report else { return }
        notices.report(report, skillName: skillName(report.skill))
    }

    /// Applies the levels banked experience has earned. The skills menu calls it as it
    /// opens, which is when the game raises the level. Nil without leveling.
    @discardableResult
    public func applyEarnedLevels() -> PlayerLevelUpReport? {
        guard let leveling else { return nil }
        let report = leveling.applyEarnedLevels()
        skills?.noteCharacterLevels(report.levelsGained)
        notices.reportLevel(report)
        return report
    }
}

/// Crafting reports through the same method combat's adapters call.
extension ProgressionCoordinator: SkillUseReporting {}

extension SkillAdvancementRuntime {
    init(_ data: ProgressionSessionData, information: ActorValueInformationStore) {
        self.init(
            values: data.values,
            parameters: SkillUseParameterSource(store: information),
            settings: data.skillSettings
        )
    }
}

nonisolated extension SkillUseEvent {
    private static let speechCheckUse: Float = 75

    /// The player's use for a won speech check, by their base Speech.
    static func speechCheckWon(speech level: Float) -> SkillUseEvent {
        SkillUseEvent(actor: .player, action: .speechCheck, amount: speechCheckUse * level)
    }
}
