// Training: a trainer's class names a skill and a level; the player pays gold for
// one skill point, at most five times per level. See docs/engine/training.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyProgressionInterface

extension ProgressionCoordinator {
    /// UESP "Skyrim:Trainers": a session costs gold by the current level and gives a
    /// level's worth of skill experience. The notice for a refusal goes to the HUD.
    @discardableResult
    public func train(with offer: TrainerOffer) -> TrainingOutcome {
        guard let leveling, var skills else { return .unavailable }
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
            pendingCommands.append(.showNotification(training.text(for: refusal)))
            return .refused(refusal)
        }
        guard world.payTrainer(cost, to: offer.trainer) else {
            pendingCommands.append(.showNotification(training.insufficientGoldText))
            return .refused(.insufficientGold)
        }
        let report = skills.train(skill: offer.skill, on: skills.player)
        store(skills, report: report)
        leveling.noteTrainingSession()
        pendingCommands.append(.incrementStat("Training Sessions"))
        return .trained(skill: offer.skill, level: level + 1, gold: cost)
    }

    /// The readout's Train control: one session with the nearest trainer.
    @discardableResult
    func trainWithNearestTrainer() -> ProgressionActionOutcome {
        guard let offer = world.nearestTrainer() else { return record(.noTrainer) }
        let skill = ActorValueIdentity.name(at: offer.skill) ?? "skill \(offer.skill)"
        return switch train(with: offer) {
        case let .trained(_, level, gold):
            record(.trained(
                trainer: offer.name, skill: skill, level: level, gold: gold,
                session: leveling?.state.trainingSessions ?? 0
            ))
        case let .refused(refusal):
            record(.trainingRefused(
                trainer: offer.name, skill: skill, maximum: offer.maximumLevel, refusal
            ))
        case .unavailable:
            record(.unavailable)
        }
    }
}
