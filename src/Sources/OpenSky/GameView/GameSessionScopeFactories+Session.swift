// The coordinators built over the session's first stage: the streamer, the frame
// session, and the loaded world. Without a stage, as in a test, each is built without
// game data (docs/decisions/session-scope.md).

import Foundation
import OpenSkyActorAdapters
import OpenSkyAIAdapters
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatAdapters
import OpenSkyEffects
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryAdapters
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicAdapters
import OpenSkyMagicInterface
import OpenSkyMenuAdapters
import OpenSkyProgression
import OpenSkyScriptAdapters
import OpenSkyScripting
import OpenSkyStoryAdapters
import OpenSkyWorld

extension GameSessionScopeFactories {
    /// The VM and its world bridge; nothing without the install's script files.
    func makeScripts() -> ScriptCoordinator {
        let world = scope.scriptWorld
        guard let stage = scope.stage, let fileSystem = stage.data.scriptFileSystem else {
            return ScriptCoordinator(world: world)
        }
        let bridge = world.makeBridge(
            provider: stage.data, gameSession: stage.gameSession, streamer: stage.streamer,
            worldState: scope.worldState
        )
        scope.storyWorld.fillStoryNatives(&bridge.storyNatives, &bridge.sessionNatives)
        return ScriptCoordinator(world: world, bridge: bridge, fileSystem: fileSystem)
    }

    /// The crime reporter joins the take path through the seams.
    func makeInventory() -> InventoryCoordinator {
        let world = scope.inventoryWorld
        guard
            let stage = scope.stage,
            var data = world.sessionData(
                provider: stage.data, streamer: stage.streamer, store: scope.worldState
            )
        else {
            return InventoryCoordinator(world: world, lockWorld: scope.lockWorld, data: nil)
        }
        let provider = stage.data
        data.vendors = InventoryWorldAdapter.vendorCore(provider: provider).map { core in
            VendorCoordinator(
                core: core,
                world: world,
                restockSettings: VendorRestockSettings.resolve(store: provider.gameSettings)
            )
        }
        return InventoryCoordinator(
            world: world,
            lockWorld: scope.lockWorld,
            data: data,
            seams: InventorySeams(
                recipeConditions: world, skillUses: scope.progression,
                storyEvents: scope.storyWorld
            )
        )
    }

    func makeMagic() -> MagicCoordinator {
        let world = scope.magicWorld
        guard let stage = scope.stage else { return MagicCoordinator(world: world) }
        let magic = MagicCoordinator(
            world: world, data: world.sessionData(provider: stage.data, store: scope.worldState),
            storyEvents: scope.storyWorld
        )
        // `Mod Spell Cost` folds through the caster's own copy of the perks.
        magic.caster?.perks = scope.perks.runtime
        return magic
    }

    func makeEffects() -> EffectsCoordinator {
        guard let stage = scope.stage else { return EffectsCoordinator() }
        let provider = stage.data
        let effects = provider.effectRecords.map { records in
            EffectsCoordinator(
                records: records,
                meshes: EffectsWorldAdapter.meshes(
                    provider: provider, renderer: stage.gameSession.renderer
                ),
                blood: BloodEffectSettings
                    .resolve(store: provider.gameSettings) { [unowned scope] in
                        scope.mapWorld.text($0)
                    },
                world: scope.effectsWorld
            )
        } ?? EffectsCoordinator()
        effects.absorbVisualSeconds = max(
            0, MagicWorldSettings.resolve(store: provider.gameSettings).absorbVisualSeconds
        )
        effects.posing = scope.effectModelPoser
        return effects
    }

    func makeCombat() -> CombatCoordinator {
        let world = scope.combatWorld
        let combat = CombatCoordinator(
            world: world, data: world.sessionData(), explosions: scope.effectsWorld.makeExplosions()
        )
        guard scope.stage != nil else { return combat }
        let store = scope.playerSettingsStore
        combat.load(settings: store)
        // The launcher page writes the switch while a session runs.
        store.observe { [weak combat, weak store] id in
            guard id == .combatTemperament || id == .combatGameSettings, let store else { return }
            combat?.load(settings: store)
        }
        return combat
    }

    func makeFurniture() -> FurnitureCoordinator {
        let furniture = FurnitureCoordinator(world: scope.aiWorld)
        guard scope.stage != nil else { return furniture }
        let store = scope.playerSettingsStore
        furniture.isEnabled = store.bool(.furniture)
        // The launcher page writes the switch while a session runs.
        store.observe { [weak furniture, weak store] id in
            guard id == .furniture, let store else { return }
            furniture?.isEnabled = store.bool(.furniture)
        }
        return furniture
    }

    func makeLoadingWorld() -> LoadingScreenWorldAdapter {
        let world = LoadingScreenWorldAdapter(
            game: scope.ports,
            stage: scope.stage,
            clock: { Date() }
        )
        world.state.bringFollowers = { [weak scope] scene in
            scope?.followerCommandWorld.bringFollowers(into: scene)
        }
        return world
    }
}
