public import OpenSkyGameData
public import OpenSkyProgressionInterface

/// What the world adapters use of `ProgressionCoordinator`.
public protocol ProgressionPort: AnyObject, SkillsMenuSource {
    associatedtype PlayerLevelRuntime: PlayerLevelRuntimePort
    @discardableResult func advanceSkill(_ index: Int32, byUse magnitude: Float) -> Bool
    @discardableResult func applyEarnedLevels() -> PlayerLevelUpReport?
    @discardableResult func awardCharacterExperience(_ amount: Float) -> ProgressionActionOutcome
    @discardableResult func incrementSkill(_ index: Int32) -> Bool
    var leveling: PlayerLevelRuntime? { get }
    @discardableResult func loseJailProgress(days: Int, maximumDays: Int) -> [Int32]
    func modifyPerkPoints(by delta: Int) -> Int?
    @discardableResult func reportSkillUse(_ use: SkillUseEvent) -> Float
    @discardableResult func reportSpeechCheckWon() -> Float
    var skillsMenuPlayer: SkillsMenuPlayer { get }
    var skillsMenuSkills: [SkillsMenuSkill] { get }
    @discardableResult func train(with offer: TrainerOffer) -> TrainingOutcome
    var training: TrainingSettings { get }
}
