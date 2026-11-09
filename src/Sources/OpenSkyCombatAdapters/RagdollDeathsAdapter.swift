import OpenSkyActorPresentation
import OpenSkyActorsInterface
public import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyCrimeInterface
import OpenSkyEffects
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `RagdollDeathsAdapter` reads from the session.
@MainActor
public protocol RagdollDeathsHost: AnyObject {
    var actorValues: any ActorValuePort { get }
    var containerMenu: any ContainerMenuPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var inventory: any InventoryPort { get }
    var magic: any MagicPort { get }
    var scripts: any ScriptPort { get }
    var storyWorld: any StoryWorldPort { get }
    var streamer: any CellStreamerPort { get }
    var worldData: WorldDataStores? { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `RagdollWorldAdapter`, over its own narrow host.
public struct RagdollDeathsAdapter {
    public let game: any RagdollDeathsHost
    public let poseReads: RagdollPoseReadsAdapter
}

extension RagdollDeathsAdapter {
    public func queueActorDeathEvents(for key: ReferenceKey, killer: ReferenceKey?) -> Int {
        if game.scripts.bridge?.silentDeath != key {
            game.storyWorld.reportKill(victim: key, killer: killer)
        }
        game.scripts.bridge?.recordKill(victim: key, killer: killer)
        game.magic.noteDeath(of: key, killer: killer)
        clearLocations(afterDeathOf: key)
        grantDeathItem(to: key)
        return game.scripts.runtime?.queueActorDeath(actor: key, killer: killer) ?? 0
    }

    /// A location whose last living, enabled boss died clears itself
    /// (docs/formats/locations.md).
    private func clearLocations(afterDeathOf victim: ReferenceKey) {
        guard let store = game.worldData?.locationStore, let bridge = game.scripts.bridge
        else { return }
        let world = game.worldState
        let streamer = game.streamer
        let enable = EnableParentResolver(
            delta: { world.delta(for: $0) },
            parent: { streamer.referenceEntry(formID: $0) }
        )
        let cleared = store.locationsCleared(byDeathOf: victim) { boss in
            if world.component(ActorDeathState.self, for: boss)?.isDead == true {
                return true
            }
            if let entry = streamer.referenceEntry(key: boss) {
                return !enable.isEnabled(entry)
            }
            return world.component(ReferenceEnableState.self, for: boss)?.isEnabled == false
        }
        for location in cleared {
            bridge.markLocationCleared(
                ReferenceKey(resolved: location), playsMusic: store.playsClearedMusic(location)
            )
        }
    }

    /// The death item rolls at the actor's own level (docs/engine/leveled-lists.md).
    private func grantDeathItem(to key: ReferenceKey) {
        guard
            let values = game.actorValues.runtime,
            let holder = poseReads.holder(of: key)
        else { return }
        game.inventory.grantDeathItem(to: key, actorLevel: values.baseline(of: holder).level)
    }

    public var selectedRagdollActor: ReferenceKey? {
        let streamer = game.streamer
        if
            let target = streamer.interactionTarget,
            let entry = streamer.referenceEntry(formID: target.interaction.reference),
            entry.placedActor != nil
        {
            return entry.key
        }
        return playerFeetPosition.flatMap { streamer.nearestActorEntry(to: $0)?.key }
    }

    public var playerFeetPosition: SIMD3<Float>? {
        game.gameSession?.walkController.feetPosition
    }

    /// An ACHR's holder re-derives its baseline from the NPC_'s CNTO list, as
    /// a chest's does, so the corpse needs no new menu.
    public func searchCorpse(_ key: ReferenceKey) -> Bool {
        let streamer = game.streamer
        guard
            game.inventory.runtime != nil,
            let actor = streamer.referenceEntry(key: key)?.placedActor
        else { return false }
        game.containerMenu.target(
            InventoryHolder(
                key: key, owner: .actor(base: actor.base), cell: streamer.cellLocation(of: key)
            ),
            name: "Corpse \(key.description)"
        )
        return true
    }
}
