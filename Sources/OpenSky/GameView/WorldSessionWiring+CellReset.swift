// App side of `CellResetCoordinator`: answers its record questions from the load-order
// stores and runs it around the scripts' cell attach (docs/engine/cell-reset.md).

import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld
import OpenSkyWorldState

extension WorldSessionWiring {
    /// After `wirePapyrus`, so the reset wraps the scripts' attach and detach.
    func wireCellReset(
        provider: WorldDataStores,
        gameSession: GameSession,
        streamer: CellStreamer
    ) {
        let store = game.worldState
        let reset = CellResetCoordinator(
            store: store, settings: provider.cellResetSettings
        ) { [weak gameSession] in gameSession?.gameTime.clock }
        reset.respawns = Self.respawnPolicy(provider: provider)
        reset.neverResets = { scene in
            guard let zone = scene.encounterZone, let plugin = scene.ownerPluginName else {
                return false
            }
            return provider.encounterZoneStore?.resolve(zone, fromPlugin: plugin)?
                .zone.flags.contains(.neverResets) ?? false
        }
        reset.isCleared = { [weak store] scene in
            guard
                let link = scene.locationLink, let plugin = scene.ownerPluginName,
                let location = provider.locationStore?.resolvedID(link, fromPlugin: plugin)
            else { return false }
            return store?.component(
                ScriptedReferenceState.self,
                for: ReferenceKey(resolved: location)
            )?
                .flag(ScriptedStateName.cleared) == true
        }
        gameSession.cellReset = reset
        let scripts = game.scripts
        let attached = streamer.onCellAttached
        streamer.onCellAttached = { [weak reset, weak scripts] scene, first in
            let keys = first ? reset?.cellAttached(scene) ?? [] : []
            scripts?.runtime?.prepareReset(of: keys)
            attached?(scene, first)
            scripts?.runtime?.enqueueReset(of: keys)
        }
        let detached = streamer.onCellDetached
        streamer.onCellDetached = { [weak reset] location in
            detached?(location)
            reset?.cellDetached(location)
        }
    }

    /// An actor or container respawns only with its base's respawn flag; any other
    /// reference, such as a door or a trap, always returns to its plugin state.
    private static func respawnPolicy(provider: WorldDataStores)
        -> (RuntimeReferenceEntry) -> Bool
    {
        let baselines = provider.inventoryBaselines
        return { entry in
            if let actor = entry.placedActor {
                return baselines?.actors.actors[actor.base.rawValue]?.flags
                    .contains(.respawns) ?? false
            }
            guard let base = entry.placedReference?.base else { return true }
            guard let container = baselines?.items.container(base) else { return true }
            return container.flags.contains(.respawns)
        }
    }
}
