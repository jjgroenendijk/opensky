import Foundation
public import OpenSkyGameData

nonisolated public enum ProgressionActionOutcome: Equatable, Sendable {
    case idle
    case unavailable
    case noPerk
    case skillAdvanced(SkillAdvanceReport, skill: String)
    case skillUnchanged(skill: String, verb: String)
    case experienceAwarded(Float, PlayerLevelUpReport, nextLevelAt: Float)
    case levelsApplied(PlayerLevelUpReport)
    case attributeChosen(ActorValueKind, picksOwed: Int)
    case progressRefused(PlayerProgressError)
    case perkPointsChanged(delta: Int, unspent: Int)
    case perkPointSpent(perk: String, left: Int)
    case perkChanged(perk: String, granted: Bool, changed: Bool)
    case treeRefused(PerkTreeResetRefusal)
    case madeLegendary(skill: String, refunded: Int)
    case treeReset(skill: String, refunded: Int)
    case noTrainer
    case trained(trainer: String, skill: String, level: Int, gold: Int, session: Int)
    case trainingRefused(trainer: String, skill: String, maximum: Int, TrainingRefusal)
}
