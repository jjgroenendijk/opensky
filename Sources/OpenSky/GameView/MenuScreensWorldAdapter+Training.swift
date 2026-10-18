// The training menu's reads and writes: the trainer's offer, the player's skill and
// gold, and one paid session through the progression rule.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyProgression
import OpenSkyProgressionInterface

extension MenuScreensWorldAdapter: TrainingMenuWorld {
    var nearestTrainer: ReferenceKey? {
        game.progressionWorld.nearestTrainer()?.trainer
    }

    func trainingCard(trainer: ReferenceKey) -> TrainingCard? {
        guard let offer = game.progressionWorld.trainerOffer(for: trainer) else { return nil }
        let progression = game.progression
        let skill = progression.skillsMenuSkills.first { $0.index == offer.skill }
        let level = Int(skill?.level ?? 0)
        let name = skill?.name ?? ActorValueIdentity.name(at: offer.skill) ?? ""
        let sessions = progression.leveling?.state.trainingSessions ?? 0
        return TrainingCard(
            skill: (name, level, skill?.progress ?? 0),
            trainer: (offer.name, offer.maximumLevel),
            sessions: (Int(sessions), TrainingSettings.sessionsPerLevel),
            cost: progression.training.cost(skillLevel: level),
            gold: game.progressionWorld.playerGold()
        )
    }

    func train(with trainer: ReferenceKey) -> String? {
        guard let offer = game.progressionWorld.trainerOffer(for: trainer) else {
            return "No trainer"
        }
        let training = game.progression.training
        return switch game.progression.train(with: offer) {
        case .trained: nil
        case .refused(.insufficientGold): training.insufficientGoldText
        case let .refused(refusal): training.text(for: refusal)
        case .unavailable: "No game"
        }
    }
}
