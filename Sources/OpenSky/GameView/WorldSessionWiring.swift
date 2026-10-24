// The composition root of a game session: builds the cell streamer and wires
// every system to it and to the renderer, in dependency order.

import Foundation
import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyPerception
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `WorldSessionWiring` reads from the session. `GameViewController` conforms.
@MainActor
protocol WorldSessionWiringHost: AnimationEventWorldHost {
    var actorWorld: ActorWorldAdapter { get }
    var aiWorld: AIWorldAdapter { get }
    var audio: AudioCoordinator { get }
    var audioFileSystem: (any GameFileSource)? { get }
    var audioWorld: AudioWorldAdapter { get }
    var cameraInput: CameraInputState { get }
    var cinematicWorld: CinematicCameraWorldAdapter { get }
    var combatWorld: CombatWorldAdapter { get }
    var crimeWorld: CrimeWorldAdapter { get }
    var dialogueWorld: DialogueWorldAdapter { get }
    var effectsWorld: EffectsWorldAdapter { get }
    var factionWorld: FactionWorldAdapter { get }
    var hazardWorld: HazardWorldAdapter { get }
    var hud: HUDCoordinator { get }
    var idleWorld: IdleWorldAdapter { get }
    var inventoryWorld: InventoryWorldAdapter { get }
    var mountWorld: MountWorldAdapter { get }
    var loadingWorld: LoadingScreenWorldAdapter { get }
    var lockWorld: LockWorldAdapter { get }
    var perkActivationWorld: PerkActivationWorldAdapter { get }
    var magicWorld: MagicWorldAdapter { get }
    var mapWorld: MapWorldAdapter { get }
    var messageWorld: MessageWorldAdapter { get }
    var npcAnimation: NPCAnimationCoordinator { get }
    var objectAnimationWorld: ObjectAnimationWorldAdapter { get }
    var actorGraphWorld: ActorGraphWorldAdapter { get }
    var perception: PerceptionCoordinator { get }
    var playerWorld: PlayerWorldAdapter { get }
    var progressionWorld: ProgressionWorldAdapter { get }
    var raceMenu: RaceMenuCoordinator { get }
    var ragdollWorld: RagdollWorldAdapter { get }
    var runtimeState: RuntimeStateCoordinator { get }
    var scriptWorld: ScriptWorldAdapter { get }
    var scripts: ScriptCoordinator { get }
    var storyWorld: StoryWorldAdapter { get }
    var streamer: CellStreamer? { get set }
    var swfMovies: SWFMovieSource { get }
    var trapControl: TrapControlAdapter { get }
    var vehicleWorld: VehicleWorldAdapter { get }
    var worldState: WorldStateStore { get }
}

final class WorldSessionWiring {
    unowned let game: any WorldSessionWiringHost
    /// Actor clips for idles, gaits, and combat reactions, loaded off the main actor.
    private(set) var animationClips: ActorClipLoader?
    private(set) lazy var animationEvents = AnimationEventWorldAdapter(game: game)

    init(game: any WorldSessionWiringHost) {
        self.game = game
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

    func wireStreaming(session: CellSession, gameSession: GameSession) {
        let renderer = gameSession.renderer
        let provider = session.data
        let streamer = CellStreamer(
            center: CellCoordinate(x: FirstRenderCell.gridX, y: FirstRenderCell.gridY),
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
        streamer.doors = DoorSettings.resolve(store: provider.gameSettings)
        renderer.attachTextureStreaming(to: session.runner)
        wireAnimationAssets(gameSession: gameSession)
        wireMenuMovies(gameSession: gameSession)
        game.aiWorld.wireAIOverlay(renderer: renderer, streamer: streamer)
        game.runtimeState.reloadGlobals()
        game.runtimeState.calendarTexts = CalendarTexts
            .resolve(store: provider.gameSettings) { [game] in game.mapWorld.text($0) }
        game.raceMenu.morphCounts = FaceMorphCounts.resolve(store: provider.gameSettings)
        game.aiWorld.wireNPCMovement(gameSession: gameSession, streamer: streamer)
        streamer.bind(to: game.worldState)
        wireFrame(gameSession: gameSession, streamer: streamer)
        game.audioWorld.wireAudioCallbacks(streamer)
        // After the audio callbacks, so the engine's own interaction handling
        // stays first in the multicast order.
        game.scriptWorld.wirePapyrus(
            provider: provider,
            gameSession: gameSession,
            streamer: streamer
        )
        wireAssetDrains(gameSession: gameSession)
        game.messageWorld.wire(gameSession: gameSession)
        // Ownership reads the FACT store, and the reporter joins the take path.
        game.crimeWorld.wireCrime(provider: provider)
        // Last in the multicast order: the activation sound and the recorded
        // activation both land before the item leaves the world.
        game.inventoryWorld.wireWorldItems(provider: provider, streamer: streamer)
        game.lockWorld.wireLocks(provider: provider, streamer: streamer, gameSession: gameSession)
        game.perkActivationWorld.wire(streamer: streamer)
        // After the item runtime, which owns the equipped set of the body.
        game.playerWorld.wirePlayerBody(session: session, gameSession: gameSession)
        wireActorSystems(provider: provider, gameSession: gameSession)
        game.hazardWorld.wireHazards(
            provider: provider,
            streamer: streamer,
            gameSession: gameSession
        )
        game.effectsWorld.wireEffects(
            provider: provider,
            streamer: streamer,
            gameSession: gameSession
        )
        game.trapControl.wire(renderer: gameSession.renderer)
        game.combatWorld.wireMelee(provider: provider, gameSession: gameSession)
        game.combatWorld.wireArchery(provider: provider, gameSession: gameSession)
        game.ragdollWorld.wireRagdoll(gameSession: gameSession)
        game.playerWorld.wireActorState(gameSession: gameSession)
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
            streamer?.collisionCandidates(overlapping: bounds) ?? []
        }
        gameSession.locomotion.sampleWater = { [weak streamer] position in
            streamer?.sampleWaterHeight(at: position)
        }
        streamer.onWorldspaceChanged.add { [weak gameSession] editorID in
            gameSession?.weather?.setWorldspace(editorID: editorID)
        }
    }

    /// Menu movies decode off the main actor, so a menu opens without a stall.
    func wireMenuMovies(gameSession: GameSession) {
        let movies = game.swfMovies
        movies.prefetch(SWFMovieSource.menuMoviePaths)
        gameSession.assetDrains.register(.menuMovies) { _ in movies.drain() }
    }

    /// One clip loader for idles, gaits, and combat reactions. Its results enter
    /// before the world tick, and the coordinators that wait on it go right after.
    private func wireAnimationAssets(gameSession: GameSession) {
        guard let files = game.audioFileSystem else { return }
        let clips = ActorClipLoader.clips(files: files)
        animationClips = clips
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
        let input = game.cameraInput
        let frameSteps = gameSession.frameSteps
        let mounts = game.mountWorld
        let mountTakesPress = { [weak mounts] in mounts?.takeActivation() == true }
        frameSteps.register(.streaming) { [weak streamer, weak gameSession, weak input] position in
            // A rider's use key dismounts instead of activating the world.
            let pressed = input?.consumeActivation() ?? false
            let activate = pressed && !mountTakesPress()
            streamer?.update(
                cameraPosition: position,
                interactionRay: gameSession.flatMap(Self.interactionRay(of:)),
                activate: activate,
                playerCapsule: gameSession.flatMap(Self.playerCapsule(of:)),
                frameTime: gameSession?.lastCameraDelta ?? 0
            )
        }
        // The center cell's regions feed region-weighted weather selection, on
        // the draw loop's thread.
        streamer.onCenterRegionsChanged = { [weak gameSession] regions in
            gameSession?.weather?.setRegions(regions)
        }
        streamer.onInteractionTargetChanged = { [weak game] target in
            game?.hud.updateTarget(game?.inventoryWorld.labelled(target))
        }
    }

    /// Magic effects write through the actor-value runtime, so it comes first.
    private func wireActorSystems(provider: WorldDataStores, gameSession: GameSession) {
        game.actorWorld.wireActorValues(provider: provider, gameSession: gameSession)
        game.magicWorld.wireMagic(provider: provider, gameSession: gameSession)
        // After the cast loop, which folds spell cost through `Mod Spell Cost`.
        game.progressionWorld.wirePerks(provider: provider)
        // Memberships resolve through the actor-value template chain.
        game.factionWorld.wireFactions(provider: provider)
        game.progressionWorld.wireSkills(provider: provider)
        game.progressionWorld.wireProgression(provider: provider)
    }

    private func wireLateWorldSystems(
        provider: WorldDataStores,
        gameSession: GameSession,
        streamer: CellStreamer
    ) {
        game.combatWorld.wireLoop(provider: provider, gameSession: gameSession)
        game.aiWorld.wirePackages(provider: provider, gameSession: gameSession)
        game.aiWorld.wirePerception(provider: provider, gameSession: gameSession)
        game.idleWorld.wireIdles(provider: provider, gameSession: gameSession)
        game.actorGraphWorld.wire(gameSession: gameSession)
        game.vehicleWorld.wireVehicles(gameSession: gameSession)
        game.aiWorld.wireFurniture(gameSession: gameSession)
        // After the locks, whose activation gate it wraps.
        game.mountWorld.wireMounts(gameSession: gameSession)
        game.objectAnimationWorld.wire(gameSession: gameSession)
        animationEvents.wire(gameSession: gameSession)
        // The perception pass answers "did anybody see it" for every crime.
        game.crimeWorld.attachWitnesses(perception: game.perception.runtime)
        // The Talk filter reads the death and hostility state the systems above keep.
        game.dialogueWorld.wireDialogue(provider: provider, streamer: streamer)
        game.dialogueWorld.wireDialogueCamera(gameSession: gameSession)
        // Scenes speak through the dialogue index, so they come after it.
        game.storyWorld.wireStory(provider: provider, gameSession: gameSession)
        game.cinematicWorld.wire(gameSession: gameSession)
        game.loadingWorld.wire(streamer: streamer, gameSession: gameSession)
        // It wraps the scripts' cell attach, so it comes after `wirePapyrus`.
        wireCellReset(provider: provider, gameSession: gameSession, streamer: streamer)
    }

    /// Player-controlled modes only: the fly camera never picks up a target.
    /// Third person aims along the view direction from the orbit position.
    private static func interactionRay(of gameSession: GameSession) -> InteractionRay? {
        guard gameSession.movementMode.isPlayerControlled else { return nil }
        return InteractionRay(
            origin: gameSession.freeFlyCamera.position,
            direction: gameSession.freeFlyCamera.forward
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
