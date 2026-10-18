// App side of training: the nearest actor's class, the player's gold, and the
// notice. The rule is in `ProgressionCoordinator+Training.swift`.

import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMenus
import OpenSkyProgression
import OpenSkyQuestsInterface

extension ProgressionWorldAdapter {
    func nearestTrainer() -> TrainerOffer? {
        game.actorWorld.nearestActorValueHolder().flatMap(offer(of:))
    }

    /// The actor's class training, or nil when the actor does not train.
    func trainerOffer(for key: ReferenceKey) -> TrainerOffer? {
        game.actorWorld.actorValueHolder(for: key).flatMap(offer(of:))
    }

    private func offer(of holder: ActorValueHolder) -> TrainerOffer? {
        guard
            case let .actor(base) = holder.subject,
            let resolver = game.worldData?.actorValueBaselines?
                .resolver,
            let training = resolver.characterClass(ofBase: base)?.training
        else { return nil }
        return TrainerOffer(
            trainer: holder.key,
            name: game.dialogueWorld.speakerLabel(for: holder.key),
            skill: training.skill,
            maximumLevel: training.maximumLevel
        )
    }

    func playerGold() -> Int {
        Int(game.inventory.runtime?.inventory.goldCount(of: .player) ?? 0)
    }

    /// The gold goes into the trainer's own inventory, as UESP describes.
    func payTrainer(_ gold: Int, to trainer: ReferenceKey) -> Bool {
        guard
            let inventory = game.inventory.runtime?.inventory,
            let holder = game.streamer?.inventoryHolder(of: trainer),
            inventory.goldCount(of: .player) >= gold,
            (try? inventory.remove(inventory.goldFormID, count: Int32(gold), from: .player)) != nil
        else { return false }
        _ = try? inventory.add(inventory.goldFormID, count: Int32(gold), to: holder)
        return true
    }

    func run(_ commands: [ProgressionCommand]) {
        for command in commands {
            switch command {
            case let .showNotification(text): game.hud.showNotification(text)
            case let .incrementStat(name): game.worldState.incrementMiscStat(name)
            }
        }
    }
}
