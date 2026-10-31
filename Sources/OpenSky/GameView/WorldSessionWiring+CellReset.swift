// App side of `CellResetCoordinator`: answers its record questions from the load-order
// stores and runs it around the scripts' cell attach (docs/engine/cell-reset.md).

import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld
import OpenSkyWorldState

extension WorldSessionWiring {
    /// After `buildScripts`, so the reset wraps the scripts' attach and detach.
    func wireCellReset(
        provider: WorldDataStores,
        gameSession: GameSession,
        streamer: CellStreamer
    ) {
        let store = game.worldState
        var queries = CellResetQueries()
        queries.respawns = Self.respawnPolicy(provider: provider)
        queries.neverResets = { scene in
            guard let zone = scene.encounterZone, let plugin = scene.ownerPluginName else {
                return false
            }
            return provider.encounterZoneStore?.resolve(zone, fromPlugin: plugin)?
                .zone.flags.contains(.neverResets) ?? false
        }
        queries.isCleared = { [weak store] scene in
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
        let reset = CellResetCoordinator(
            store: store, settings: provider.cellResetSettings, queries: queries
        ) { [weak gameSession] in gameSession?.gameTime.clock }
        gameSession.cellReset = reset
        let scripts = game.scripts
        // The prepare step hands its keys to the enqueue step of the same attach.
        var resetKeys: [ReferenceKey] = []
        streamer.onCellAttached.register(.resetPrepare) { [weak reset, weak scripts] attachment in
            resetKeys = attachment.isFirstIntegration
                ? reset?.cellAttached(attachment.scene) ?? [] : []
            scripts?.runtime?.prepareReset(of: resetKeys)
        }
        wireLeveledRolls(provider: provider, streamer: streamer) { resetKeys }
        streamer.onCellAttached.register(.resetEnqueue) { [weak scripts] _ in
            scripts?.runtime?.enqueueReset(of: resetKeys)
            resetKeys = []
        }
        streamer.onCellDetached.register(.reset) { [weak reset, weak store] location in
            reset?.cellDetached(location)
            store?.dropEyeTextures(in: location)
        }
    }

    /// Freezes the level of each new or reset reference that rolls a leveled list. A
    /// reset one rolls again at a level its cell was not built with, so the cell rebuilds.
    private func wireLeveledRolls(
        provider: WorldDataStores, streamer: CellStreamer,
        resetKeys: @escaping () -> [ReferenceKey]
    ) {
        guard let baselines = provider.inventoryBaselines else { return }
        let store = game.worldState
        streamer.onCellAttached.register(.leveledRolls) { [weak store, weak streamer] attachment in
            guard attachment.isFirstIntegration, let store else { return }
            let frozen = LeveledRollFreeze.freeze(
                attachment.scene, level: baselines.leveling.playerLevel.level, in: store
            ) { baselines.rollsLeveledLists(Self.inventoryOwner(of: $0, baselines: baselines)) }
            guard !Set(frozen).isDisjoint(with: resetKeys()) else { return }
            streamer?.noteStateMutation(
                in: attachment.scene.location, sequence: store.nextJournalSequence
            )
        }
    }

    private static func inventoryOwner(
        of entry: RuntimeReferenceEntry, baselines: InventoryBaselineResolver
    ) -> InventoryOwner {
        if let actor = entry.placedActor {
            return .actor(base: actor.base)
        }
        guard let base = entry.placedReference?.base, baselines.items.container(base) != nil else {
            return .generated
        }
        return .container(base: base)
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
            guard
                let base = entry.placedReference?.base,
                let container = baselines?.items.container(base) else { return true }
            return container.flags.contains(.respawns)
        }
    }
}
