// What the last progression action did, as a value. Only the formatter below
// builds sentences (docs/engine/coordinators.md).

import Foundation
import OpenSkyGameData

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

nonisolated extension ProgressionActionOutcome {
    static let unavailableText = "Progression unavailable: no game data loaded."

    /// `training` holds the load order's refusal notices.
    public func text(training: TrainingSettings) -> String {
        switch self {
        case .idle: "No leveling action yet."
        case .unavailable: Self.unavailableText
        case .noPerk: "This box grants no perk."
        case let .skillAdvanced(report, skill):
            ProgressionControlReadout.advanceText(report, skillName: skill)
        case let .skillUnchanged(skill, verb):
            "\(skill) \(verb): this load order carries no advancement parameters for it."
        case let .experienceAwarded(amount, report, nextLevelAt):
            Self.awardText(amount, report, nextLevelAt: nextLevelAt)
        case let .levelsApplied(report):
            report.didLevel ? Self.awardText(0, report, nextLevelAt: 0) : "No earned level waits."
        case let .attributeChosen(kind, picksOwed):
            String(format: "Chose %@: %d pick(s) still owed.", kind.rawValue, picksOwed)
        case let .progressRefused(error): Self.text(for: error)
        case let .perkChanged(perk, granted, changed): Self.perkText(perk, granted, changed)
        case let .treeRefused(refusal): Self.text(for: refusal)
        case .perkPointsChanged, .perkPointSpent, .madeLegendary, .treeReset, .noTrainer,
             .trained, .trainingRefused:
            pointOrTrainingText(training: training)
        }
    }

    private func pointOrTrainingText(training: TrainingSettings) -> String {
        switch self {
        case let .perkPointsChanged(delta, unspent):
            "Changed perk points by \(delta): \(unspent) unspent."
        case let .perkPointSpent(perk, left): "Spent a point on \(perk): \(left) left."
        case let .madeLegendary(skill, refunded):
            "\(skill) is legendary; refunded \(refunded) perk point(s)."
        case let .treeReset(skill, refunded):
            "Reset the \(skill) tree; refunded \(refunded) perk point(s)."
        case .noTrainer: "No trainer nearby: no resident actor's class teaches a skill."
        case let .trained(trainer, skill, level, gold, session):
            "\(trainer) trained \(skill) to \(level) for \(gold) gold "
                + "(session \(session) of \(TrainingSettings.sessionsPerLevel) this level)."
        case let .trainingRefused(trainer, skill, maximum, refusal):
            "\(trainer) (\(skill) to \(maximum)): " + training.text(for: refusal)
        default: ""
        }
    }

    private static func awardText(
        _ amount: Float, _ report: PlayerLevelUpReport, nextLevelAt: Float
    ) -> String {
        guard report.didLevel else {
            return String(
                format: "Awarded %.0f character XP: still level %d, %.0f/%.0f banked, "
                    + "%d level(s) wait for the skills menu.",
                amount, report.level, report.carriedExperience, nextLevelAt, report.levelsReady
            )
        }
        return String(
            format: "Applied levels: level %d to %d, %d perk point(s), %d pick(s) owed.",
            report.previousLevel, report.level, report.perkPoints, report.pendingAttributePicks
        )
    }

    private static func perkText(_ name: String, _ granted: Bool, _ changed: Bool) -> String {
        switch (granted, changed) {
        case (true, true): "Granted \(name)."
        case (true, false): "\(name) was already owned."
        case (false, true): "Removed \(name)."
        case (false, false): "\(name) was not owned."
        }
    }

    private static func text(for refusal: PerkTreeResetRefusal) -> String {
        switch refusal {
        case .notASkill: "Refused: not a skill."
        case .noProgression: unavailableText
        case let .belowLegendaryLevel(base):
            String(format: "Refused: the skill is %.0f, not 100.", base)
        case .noDragonSoul: "Refused: no dragon soul to spend."
        case .noPerksInTree: "Refused: no perks in this tree."
        }
    }

    /// Spelled as the rule that refused.
    private static func text(for error: PlayerProgressError) -> String {
        switch error {
        case .noAttributePickOwed: "No attribute pick is owed: gain a level first."
        case .noPerkPoints: "No perk points to spend."
        case let .perkRefused(refusal):
            "Refused: \(ProgressionControlReadout.description(of: refusal))."
        }
    }
}
