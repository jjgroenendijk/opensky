import OpenSkyAudio
public import OpenSkyCells
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMenus
public import OpenSkyProgression
public import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
public import OpenSkySessionInterface
import OpenSkyWorld

/// What `ProgressionTrainingAdapter` reads from the session.
@MainActor
public protocol ProgressionTrainingHost: AnyObject {
    var actorWorld: any ActorWorldPort { get }
    var dialogueWorld: any DialogueWorldPort { get }
    var hud: any HUDPort { get }
    var inventory: any InventoryPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var worldData: WorldDataStores? { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `ProgressionWorldAdapter`, over its own narrow host.
public struct ProgressionTrainingAdapter {
    public unowned let owner: ProgressionWorldAdapter
    public unowned let game: any ProgressionTrainingHost
}

extension ProgressionTrainingAdapter {
    public func nearestTrainer() -> TrainerOffer? {
        game.actorWorld.nearestActorValueHolder().flatMap(offer(of:))
    }

    /// The actor's class training, or nil when the actor does not train.
    public func trainerOffer(for key: ReferenceKey) -> TrainerOffer? {
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

    public func playerGold() -> Int {
        Int(game.inventory.runtime?.inventory.goldCount(of: .player) ?? 0)
    }

    /// The gold goes into the trainer's own inventory, as UESP describes.
    public func payTrainer(_ gold: Int, to trainer: ReferenceKey) -> Bool {
        guard
            let inventory = game.inventory.runtime?.inventory,
            let holder = game.streamer?.inventoryHolder(of: trainer),
            inventory.goldCount(of: .player) >= gold,
            attempt({ try inventory.remove(inventory.goldFormID, count: Int32(gold), from: .player)
            }) != nil
        else { return false }
        _ = attempt { try inventory.add(inventory.goldFormID, count: Int32(gold), to: holder) }
        return true
    }

    public func run(_ commands: [ProgressionCommand]) {
        for command in commands {
            switch command {
            case let .showNotification(text): game.hud.showNotification(text)
            case let .incrementStat(name): game.worldState.incrementMiscStat(name)
            }
        }
    }
}
