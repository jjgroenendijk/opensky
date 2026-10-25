// The coordinators that need the cell streamer or the frame session, built at session
// start. Each adapter then joins them to the frame (docs/decisions/session-scope.md).

import OpenSkyActorPresentation
import OpenSkyCells
import OpenSkyEffects
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyScripting
import OpenSkyWorld

extension WorldSessionWiring {
    /// The VM and its world bridge; nothing without the install's script files.
    func buildScripts(provider: WorldDataStores, gameSession: GameSession, streamer: CellStreamer) {
        guard let fileSystem = provider.scriptFileSystem else { return }
        let world = game.scriptWorld
        let bridge = world.makeBridge(
            provider: provider, gameSession: gameSession, streamer: streamer
        )
        let scripts = ScriptCoordinator(world: world, bridge: bridge, fileSystem: fileSystem)
        game.scripts = scripts
        world.wireScripts(
            scripts,
            resolver: provider.scriptFormIDResolver,
            gameSession: gameSession,
            streamer: streamer
        )
    }

    /// After the audio and Papyrus subscribers, so the activation sound plays
    /// whether or not the take succeeds. The crime reporter joins the take path.
    func buildWorldItems(provider: WorldDataStores, streamer: CellStreamer) {
        let world = game.inventoryWorld
        guard var data = world.sessionData(provider: provider, streamer: streamer) else { return }
        data.vendors = InventoryWorldAdapter.vendorCore(provider: provider).map { core in
            VendorCoordinator(
                core: core,
                world: world,
                restockSettings: VendorRestockSettings.resolve(store: provider.gameSettings)
            )
        }
        game.inventory = InventoryCoordinator(
            world: world,
            lockWorld: game.lockWorld,
            data: data,
            seams: InventorySeams(
                recipeConditions: world, skillUses: game.progression, storyEvents: game.storyWorld
            )
        )
        world.wireWorldItems(streamer: streamer)
    }

    /// After the actor values, because every effect writes an actor value, and after
    /// the world items, because the spellbook reads the equipment.
    func buildMagic(provider: WorldDataStores, gameSession: GameSession) {
        let world = game.magicWorld
        game.magic = MagicCoordinator(
            world: world, data: world.sessionData(provider: provider), storyEvents: game.storyWorld
        )
        world.wireMagic(gameSession: gameSession)
    }

    func buildEffects(provider: WorldDataStores, streamer: CellStreamer, gameSession: GameSession) {
        let world = game.effectsWorld
        if let records = provider.effectRecords {
            game.effects = EffectsCoordinator(
                records: records,
                meshes: EffectsWorldAdapter.meshes(
                    provider: provider,
                    renderer: gameSession.renderer
                ),
                blood: BloodEffectSettings.resolve(store: provider.gameSettings) { [game] in
                    game.mapWorld.text($0)
                },
                world: world
            )
        }
        world.wireEffects(provider: provider, streamer: streamer, gameSession: gameSession)
    }

    func buildAnimationEvents(gameSession: GameSession) {
        gameSession.animationEvents = AnimationEventCoordinator(world: animationEvents)
        animationEvents.wire(gameSession: gameSession)
    }
}
