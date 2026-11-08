import OpenSkyActors
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCrime
import OpenSkyCrimeInterface
import OpenSkyDialogue
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `FollowerCommandTasksAdapter` reads from the session.
@MainActor
public protocol FollowerCommandTasksHost: AnyObject {
    var aiWorld: any AIWorldPort { get }
    var crime: any CrimePort { get }
    var furniture: any FurniturePort { get }
    var inventory: any InventoryPort { get }
    var inventoryWorld: any InventoryWorldPort { get }
    var scripts: any ScriptPort { get }
    var streamer: (any CellStreamerPort)? { get }
}

/// Part of `FollowerCommandWorldAdapter`, over its own narrow host.
public struct FollowerCommandTasksAdapter {
    public unowned let owner: FollowerCommandWorldAdapter
    public unowned let game: any FollowerCommandTasksHost
}

extension FollowerCommandTasksAdapter {
    /// What the rules know about `key`, or nil when it is nothing a follower can use.
    public func commandTarget(_ key: ReferenceKey) -> FollowerCommandTarget? {
        guard let entry = game.streamer?.referenceEntry(key: key) else { return nil }
        var target: FollowerCommandTarget
        if entry.placedActor != nil {
            guard let position = game.aiWorld.packageActorPosition(key) else { return nil }
            let dead = game.aiWorld.packageActorActivity(key) == .dead
            target = FollowerCommandTarget(
                key: key, kind: dead ? .corpse : .actor, position: position
            )
            target.isHostile = game.scripts.bridge?.isHostile(key, toward: .player) == true
        } else {
            guard
                let interaction = game.streamer?.residentInteraction(reference: entry.formID)
            else { return nil }
            target = FollowerCommandTarget(
                key: key, kind: FollowerCommandWorldAdapter.kind(of: interaction),
                position: interaction.position
            )
            let locks = game.inventory.locks
            if let lock = locks.lock(of: interaction), lock.state.isLocked {
                target.lock = locks.difficulty(of: lock.shown)
            }
            target.isOwned = game.crime.reporter?.verdict(on: key).isTheft == true
        }
        target.noFavorAllowed = game.scripts.bridge?.scriptedState(of: key)
            .flag(FollowerCommandWorldAdapter.noFavorAllowed) == true
        return target
    }

    public func performFollowerTask(_ task: FollowerCommandTask, follower: ReferenceKey) -> Bool {
        guard let key = task.target.key else { return false }
        if task.unlocks, !unlock(key, isCrime: task.crime != nil) {
            return false
        }
        switch task.action {
        case .activate where task.target.kind == .furniture:
            if case .success = game.furniture.use(key, by: follower) {
                return true
            }
            return false
        case .activate:
            return game.aiWorld.activate(key, by: follower) == .done
        case .moveTo:
            return true
        case .pickUp:
            return game.inventory.followerPickUp(key, by: follower)
        case .loot:
            return game.inventoryWorld.run(game.inventory.followerTakeAll(from: key, by: follower))
        case .attack:
            if task.crime == .violence {
                game.crime.reportAssault(on: key, wasHostile: false)
            }
            return game.scripts.bridge?.startActorCombat(follower, target: key) == true
        }
    }

    /// The follower opens the lock without lockpicks. Picking an owner's lock is
    /// the player's crime.
    private func unlock(_ key: ReferenceKey, isCrime: Bool) -> Bool {
        guard
            let formID = game.streamer?.referenceEntry(key: key)?.formID,
            let interaction = game.streamer?.residentInteraction(reference: formID)
        else { return false }
        _ = game.inventoryWorld.run(game.inventory.locks.setLocked(interaction, locked: false))
        if isCrime {
            _ = game.crime.reportLockpicking(of: key)
        }
        return true
    }
}
