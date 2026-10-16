// Training: a trainer's class names a skill and a level; the player pays gold for
// one skill point, at most five times per level. See docs/engine/training.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgressionInterface

/// A trainer the player can buy sessions from.
nonisolated public struct TrainerOffer: Equatable, Sendable {
    public let trainer: ReferenceKey
    public let name: String
    /// The skill's actor value index.
    public let skill: Int32
    public let maximumLevel: Int

    public init(trainer: ReferenceKey, name: String, skill: Int32, maximumLevel: Int) {
        self.trainer = trainer
        self.name = name
        self.skill = skill
        self.maximumLevel = maximumLevel
    }
}

/// What one training attempt did.
nonisolated public enum TrainingOutcome: Equatable, Sendable {
    case trained(skill: Int32, level: Int, gold: Int)
    case refused(TrainingRefusal)
    case unavailable
}

extension ProgressionCoordinator {
    /// UESP "Skyrim:Trainers": a session costs gold by the current level and
    /// raises the skill one point. The notice for a refusal goes to the HUD.
    @discardableResult
    public func train(with offer: TrainerOffer) -> TrainingOutcome {
        guard let leveling, let skills, let world else { return .unavailable }
        let level = Int(skills.level(ofSkill: offer.skill, on: skills.player))
        let cost = training.cost(skillLevel: level)
        if
            let refusal = training.refusal(
                skillLevel: level,
                trainerMaximum: offer.maximumLevel,
                sessionsThisLevel: leveling.state.trainingSessions,
                gold: world.playerGold()
            )
        {
            world.showNotification(training.text(for: refusal))
            return .refused(refusal)
        }
        guard world.payTrainer(cost, to: offer.trainer) else {
            world.showNotification(training.insufficientGoldText)
            return .refused(.insufficientGold)
        }
        incrementSkill(offer.skill)
        leveling.noteTrainingSession()
        world.incrementStat("Training Sessions")
        return .trained(skill: offer.skill, level: level + 1, gold: cost)
    }

    /// The panel's Train control: one session with the nearest trainer.
    @discardableResult
    public func trainWithNearestTrainer() -> String {
        guard let offer = world?.nearestTrainer() else {
            lastActionText = "No trainer nearby: no resident actor's class teaches a skill."
            return lastActionText
        }
        let skill = ActorValueIdentity.name(at: offer.skill) ?? "skill \(offer.skill)"
        switch train(with: offer) {
        case let .trained(_, level, gold):
            let sessions = leveling?.state.trainingSessions ?? 0
            lastActionText = "\(offer.name) trained \(skill) to \(level) for \(gold) gold "
                + "(session \(sessions) of \(TrainingSettings.sessionsPerLevel) this level)."
        case let .refused(refusal):
            lastActionText = "\(offer.name) (\(skill) to \(offer.maximumLevel)): "
                + training.text(for: refusal)
        case .unavailable:
            lastActionText = Self.noProgressionText
        }
        return lastActionText
    }
}
