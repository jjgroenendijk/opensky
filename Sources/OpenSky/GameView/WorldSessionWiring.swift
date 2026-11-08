// The composition root of a game session: builds the cell streamer and wires
// every system to it and to the renderer, in dependency order.

import Foundation
import OpenSkyActorAdapters
import OpenSkyActorPresentation
import OpenSkyAIAdapters
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatAdapters
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryAdapters
import OpenSkyMagic
import OpenSkyMagicAdapters
import OpenSkyMenuAdapters
import OpenSkyMenus
import OpenSkyObjectAnimation
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkySessionAdapters
import OpenSkySessionInterface
import OpenSkyStoryAdapters
import OpenSkyTerrain
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

final class WorldSessionWiring {
    unowned let game: GameSessionScope

    init(game: GameSessionScope, session: CellSession, gameSession: GameSession) {
        self.game = game
        buildStreaming(session: session, gameSession: gameSession)
    }

    /// Builds run off the main thread on the session's runner; the finished scene
    /// swaps in through `Renderer.setScene`. Every capture is weak, because
    /// `game` owns both the renderer and the streamer.
    private func wireAssetDrains(gameSession: GameSession) {
        let scripts = game.scripts
        gameSession.assetDrains
            .register(.scripts) { [weak scripts] _ in scripts?.drainLoads() }
        let audio = game.audio
        gameSession.assetDrains.register(.audio) { [weak audio] _ in audio?.drainLoads() }
    }

    private func buildStreaming(session: CellSession, gameSession: GameSession) {
        let renderer = gameSession.renderer
        let provider = session.data
        let streamer = CellStreamer(
            center: CellCoordinate(x: FirstRenderCell.gridX, y: FirstRenderCell.gridY),
            radius: game.terrainLODConfigurationStore.snapshot().configuration.loadedGridRadius,
            runner: session.runner,
            sink: { [weak renderer] scene, camera in
                do {
                    try renderer?.setScene(scene, camera: camera)
                } catch {
                    Self.logger.error(
                        "[ERROR] scene swap failed: \(String(describing: error), privacy: .public)"
                    )
                }
            }
        )
        streamer.placedRecords = provider.placedRecords
        gameSession.loadedGridRadius = streamer.grid.radius
        streamer.doors = DoorSettings.resolve(store: provider.gameSettings)
        renderer.attachTextureStreaming(to: session.runner)
        wireAnimationAssets(gameSession: gameSession)
        wireMenuMovies(gameSession: gameSession)
        _ = AIOverlayWiring(game.aiWorld, renderer: renderer, streamer: streamer)
        game.runtimeState.reloadGlobals()
        _ = AINPCMovementWiring(game.aiWorld, gameSession: gameSession, streamer: streamer)
        streamer.bind(to: game.worldState)
        wireFrame(gameSession: gameSession, streamer: streamer)
        _ = AudioCallbacksWiring(game.audioWorld, streamer)
        // After the audio callbacks, so the engine's own interaction handling
        // stays first in the multicast order.
        buildScripts(provider: provider, gameSession: gameSession, streamer: streamer)
        wireAssetDrains(gameSession: gameSession)
        _ = MessageWiring(game.messageWorld, gameSession: gameSession)
        // Last in the multicast order: the activation sound and the recorded
        // activation both land before the item leaves the world.
        buildWorldItems(provider: provider, streamer: streamer)
        _ = LocksWiring(game.lockWorld, streamer: streamer, gameSession: gameSession)
        _ = PerkActivationWiring(game.perkActivationWorld, streamer: streamer)
        // After the item runtime, which owns the equipped set of the body.
        _ = PlayerBodyWiring(game.playerWorld, gameSession: gameSession)
        wireActorSystems(provider: provider, gameSession: gameSession)
        _ = HazardsWiring(
            game.hazardWorld,
            provider: provider,
            streamer: streamer,
            gameSession: gameSession
        )
        buildEffects(provider: provider, streamer: streamer, gameSession: gameSession)
        _ = TrapControlWiring(game.trapControl, renderer: gameSession.renderer)
        _ = CombatMeleeWiring(game.combatWorld, gameSession: gameSession)
        _ = CombatArcheryWiring(game.combatWorld, gameSession: gameSession)
        _ = RagdollWiring(game.ragdollWorld, gameSession: gameSession)
        _ = PlayerActorStateWiring(game.playerWorld, gameSession: gameSession)
        wireLateWorldSystems(provider: provider, gameSession: gameSession, streamer: streamer)
        wireWorldQueries(gameSession: gameSession, streamer: streamer)
        game.streamer = streamer
    }

    /// The ground, collision, water, and worldspace the session reads from the streamer.
    private func wireWorldQueries(gameSession: GameSession, streamer: CellStreamer) {
        gameSession.terrainSampler = { [weak streamer] position in
            streamer?.sampleTerrain(at: position)
        }
        gameSession.collisionQuery = { [weak streamer] bounds in
            streamer?.characterCollisionCandidates(overlapping: bounds) ?? []
        }
        gameSession.characterCarry = { [weak streamer] capsule, feet in
            streamer?.dynamicBodies.characterCarry(capsule: capsule, feetPosition: feet) ?? .zero
        }
        gameSession.locomotion.sampleWater = { [weak streamer] position in
            streamer?.water(at: position)
        }
        streamer.onWorldspaceChanged.register(.weather) { [weak gameSession] editorID in
            gameSession?.weather?.setWorldspace(editorID: editorID)
        }
    }

    /// Menu movies decode off the main actor, so a menu opens without a stall.
    private func wireMenuMovies(gameSession: GameSession) {
        let movies = game.swfMovies
        movies.prefetch(SWFMovieSource.menuMoviePaths)
        gameSession.assetDrains.register(.menuMovies) { _ in movies.drain() }
    }

    /// One clip loader for idles, gaits, and combat reactions. Its results enter
    /// before the world tick, and the coordinators that wait on it go right after.
    private func wireAnimationAssets(gameSession: GameSession) {
        guard let clips = game.animationClips else { return }
        let idles = game.idleWorld.idles
        let npcAnimation = game.npcAnimation
        let assetDrains = gameSession.assetDrains
        assetDrains.register(.animationClips) { [weak idles, weak npcAnimation] _ in
            clips.drain()
            idles?.drainLoads()
            npcAnimation?.applyArrivedClips()
        }
    }

    private func wireFrame(gameSession: GameSession, streamer: CellStreamer) {
        // Published inside the frame's own update, so the poses the pass uploads
        // are the ones this frame simulated.
        streamer.onDynamicPosesChanged = { [weak gameSession] deltas in
            gameSession?.instancePoses.dynamicDeltas = deltas
        }
        streamer.onLoadDoorUsed = { [unowned game] door in
            game.objectAnimationWorld.doors.swingOpen(door.rawValue)
        }
        let input = game.cameraInput
        let frameSteps = gameSession.frameSteps
        let mounts = game.mountWorld
        let commands = game.followerCommandWorld
        let takesPress = { [weak mounts, weak commands] in
            mounts?.takeActivation() == true || commands?.takeActivation() == true
        }
        let pickReach = { [weak commands] in commands?.pickReach }
        let advanceUseKey = { [weak commands, weak gameSession, weak input] in
            commands?.advanceUseKey(
                by: gameSession?.lastCameraDelta ?? 0, isDown: input?.isActivationHeld == true
            )
        }
        frameSteps.register(.streaming) { [weak streamer, weak gameSession, weak input] position in
            // A rider's use key dismounts, and in command mode it picks the follower's
            // target, instead of activating the world.
            let pressed = input?.consumeActivation() ?? false
            let activate = pressed && !takesPress()
            advanceUseKey()
            streamer?.update(
                cameraPosition: position,
                interactionRay: gameSession.flatMap {
                    Self.interactionRay(of: $0, reach: pickReach())
                },
                activate: activate,
                playerCapsule: gameSession.flatMap(Self.playerCapsule(of:)),
                frameTime: gameSession?.lastCameraDelta ?? 0
            )
            if let walk = gameSession?.walkController {
                streamer?.recordPlayerSwim(at: walk.feetPosition, isSwimming: walk.isSwimming)
            }
        }
        // The center cell's regions feed region-weighted weather selection, on
        // the draw loop's thread.
        streamer.onCenterRegionsChanged = { [weak gameSession] regions in
            gameSession?.weather?.setRegions(regions)
        }
        streamer.onInteractionTargetChanged = { [weak game] target in
            game?.hud.updateTarget(game?.inventoryWorld.perks.labelled(target))
        }
    }

    /// Magic effects write through the actor-value runtime, so it comes first.
    private func wireActorSystems(provider: WorldDataStores, gameSession: GameSession) {
        _ = ActorValuesWiring(game.actorWorld, provider: provider, gameSession: gameSession)
        buildMagic(provider: provider, gameSession: gameSession)
    }

    private func wireLateWorldSystems(
        provider: WorldDataStores,
        gameSession: GameSession,
        streamer: CellStreamer
    ) {
        _ = CombatLoopWiring(game.combatWorld, gameSession: gameSession)
        _ = AIPackagesWiring(game.aiWorld, gameSession: gameSession)
        _ = AIPerceptionWiring(game.aiWorld.perceptionSense, gameSession: gameSession)
        _ = IdlesWiring(game.idleWorld, gameSession: gameSession)
        _ = ActorGraphWiring(game.actorGraphWorld, gameSession: gameSession)
        _ = VehiclesWiring(game.vehicleWorld, gameSession: gameSession)
        _ = AIFurnitureWiring(game.aiWorld.seating, gameSession: gameSession)
        // After the locks, whose activation gate it wraps.
        _ = MountsWiring(game.mountWorld, gameSession: gameSession)
        _ = BeastFormWiring(game.beastForms)
        _ = ActivationRefusalWiring(game.activationRefusals)
        _ = DragonFlightWiring(game.dragonFlightWorld, gameSession: gameSession)
        _ = ObjectAnimationWiring(game.objectAnimationWorld, gameSession: gameSession)
        _ = EffectGraphWiring(game.effectGraphWorld, gameSession: gameSession)
        buildAnimationEvents(gameSession: gameSession)
        // The Talk filter reads the death and hostility state the systems above keep.
        _ = DialogueWiring(game.dialogueWorld, streamer: streamer)
        _ = DialogueCameraWiring(game.dialogueWorld.cameraWiring, gameSession: gameSession)
        // Scenes speak through the dialogue index, so they come after it.
        _ = StoryWiring(game.storyWorld, provider: provider, gameSession: gameSession)
        _ = FollowerCommandWiring(game.followerCommandWorld, gameSession: gameSession)
        _ = CinematicCameraWiring(game.cinematicWorld, gameSession: gameSession)
        _ = LoadingScreenWiring(game.loadingWorld, streamer: streamer, gameSession: gameSession)
        // It wraps the scripts' cell attach, so it comes after `buildScripts`.
        buildCellReset(provider: provider, gameSession: gameSession, streamer: streamer)
    }

    /// Player-controlled modes only: the fly camera never picks up a target.
    /// Third person aims along the view direction from the orbit position.
    private static func interactionRay(
        of gameSession: GameSession, reach: Float?
    ) -> InteractionRay? {
        guard gameSession.movementMode.isPlayerControlled else { return nil }
        return InteractionRay(
            origin: gameSession.freeFlyCamera.position,
            direction: gameSession.freeFlyCamera.forward,
            maximumDistance: reach ?? InteractionRay.defaultMaximumDistance
        )
    }

    /// The feet position comes from the walk controller, because the streamer
    /// receives only the eye position.
    private static func playerCapsule(of gameSession: GameSession) -> PlayerCapsuleState? {
        guard gameSession.movementMode.isPlayerControlled else { return nil }
        return PlayerCapsuleState(
            capsule: gameSession.walkController.capsule,
            feetPosition: gameSession.walkController.feetPosition
        )
    }

    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "CellStream"
    )
}
