// Streaming setup satellite for GameViewController. Split from
// GameViewController.swift to keep that file under the strict-lint size cap
// after the M9.2.2 ambience-context subscription landed here.

import OSLog
import simd

extension GameViewController {
    /// Wires a streamer over the provider: builds run off-main on a serial
    /// runner, the recomposed scene swaps in via `Renderer.setScene`, and the
    /// renderer's per-frame hook drives the streamer with the live camera
    /// position. Weak captures both ways -> no retain cycle (this controller
    /// owns both renderer + streamer).
    func wireStreaming(provider: any CellSceneProvider, renderer: Renderer) {
        let runner = SerialCellBuildRunner(provider: provider)
        let controller = CellStreamer(
            center: CellCoordinate(x: FirstRenderCell.gridX, y: FirstRenderCell.gridY),
            runner: runner,
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
        wireStreamingSources(provider: provider, renderer: renderer, streamer: controller)
        // Runtime world state (issue #160). Every dispatched build snapshots the
        // store on the main thread, and every journalled mutation tells the
        // streamer which cell to rebuild so the change is visible without a
        // reload. Unowned-free: the store outlives the streamer, and the
        // streamer is captured weakly the other way.
        let worldState = worldState
        controller.stateSource = { worldState.snapshot() }
        worldState.onMutation = { [weak controller] location, sequence in
            controller?.noteStateMutation(in: location, sequence: sequence)
        }
        // A settled rigid body persists as an ordinary transform override
        // (issue #193), so a dropped bowl is where it rolled to after a save and
        // reload, and the cell that owns it is the one whose rebuild redraws it.
        controller.onBodySettled = { key, transform, placingCell in
            worldState.set(transform, for: key, in: placingCell)
        }
        // And until it settles, the mesh follows the body rather than waiting
        // for that rebuild. Published inside the frame's own update, below, so
        // the poses the pass uploads are the ones this frame simulated.
        controller.onDynamicPosesChanged = { [weak renderer] deltas in
            renderer?.dynamicInstanceDeltas = deltas
        }
        renderer.onFrame.add { [weak self, weak controller, weak renderer] position in
            controller?.update(
                cameraPosition: position,
                interactionRay: renderer.flatMap(Self.interactionRay(of:)),
                activate: self?.cameraInput.consumeActivation() ?? false,
                playerCapsule: renderer.flatMap(Self.playerCapsule(of:)),
                frameTime: renderer?.lastCameraDelta ?? 0
            )
        }
        // Live XCLR region feed (M7.2.3): the streamer pushes the center cell's
        // REGN set into the weather runtime so region-weighted selection runs
        // live. Same main thread as the draw loop -> WeatherSystem stays
        // single-thread-owned.
        controller.onCenterRegionsChanged = { [weak renderer] regions in
            renderer?.weather?.setRegions(regions)
        }
        controller.onInteractionTargetChanged = { [weak self] target in
            self?.updateHUDTarget(target)
        }
        wireAudioCallbacks(controller)
        // After the audio callbacks, so the engine's own interaction handling
        // stays first in the multicast order and Papyrus runs beside it.
        wirePapyrus(provider: provider, renderer: renderer, streamer: controller)
        // Last in the multicast order (issue #177): the activation sound and
        // the recorded activation both land before the item leaves the world.
        wireWorldItems(provider: provider, streamer: controller)
        // After the item runtime, which owns the equipped set the body is
        // assembled from (issue #189).
        wirePlayerBody(provider: provider, renderer: renderer)
        // After `wirePapyrus`, whose `onWorldUpdate` closure this chains onto
        // so both systems advance on the same simulated delta (issue #194).
        wireActorSystems(provider: provider, renderer: renderer)
        wireMelee(provider: provider, renderer: renderer)
        // After melee, so the two runtimes register their graph-event cursors
        // in a fixed order and a trace read from either is reproducible.
        wireArchery(provider: provider, renderer: renderer)
        // After both, for the same reason: a fixed cursor-registration order
        // keeps every runtime's view of the graph event stream reproducible.
        wireRagdoll(renderer: renderer)
        // Last of the combat systems: the loop reads what melee, archery and
        // the ragdolls did this frame, so it has to advance after all three
        // (issue #374).
        wireLateWorldSystems(provider: provider, renderer: renderer, streamer: controller)
        renderer.terrainSampler = { [weak controller] position in
            controller?.sampleTerrain(at: position)
        }
        renderer.collisionQuery = { [weak controller] bounds in
            controller?.collisionCandidates(overlapping: bounds) ?? []
        }
        renderer.locomotion.sampleWater = { [weak controller] position in
            controller?.sampleWaterHeight(at: position)
        }
        streamer = controller
    }

    private func wireStreamingSources(
        provider: any CellSceneProvider,
        renderer: Renderer,
        streamer: CellStreamer
    ) {
        wireAIOverlay(renderer: renderer, streamer: streamer)
        wireGlobals(provider: provider, renderer: renderer)
        wireNPCMovement(renderer: renderer, streamer: streamer)
    }

    /// The two runtimes that own an actor's numbers, in the order they depend
    /// on each other: magic effects write through the actor-value surface, so
    /// the surface has to exist first (issue #469).
    private func wireActorSystems(provider: any CellSceneProvider, renderer: Renderer) {
        wireActorValues(provider: provider, renderer: renderer)
        wireMagicEffects(provider: provider, renderer: renderer)
        // Last of the four: a cast spends an actor value and applies its
        // effects through the effect runtime, so both have to exist first
        // (issue #470).
        wireCasting(provider: provider, renderer: renderer)
        // The ENCH index alone, so an equipped item can resolve what it carries
        // (issue #472). It owns no runtime of its own: an enchanted hit applies
        // through the effect runtime above and its charge lives in the world-state
        // store, so there is nothing here to tick.
        wireEnchantments(provider: provider)
        // After the cast loop, which takes the perk runtime by value so a spell
        // cost folds through the `Mod Spell Cost` entry point (issue #497).
        wirePerks(provider: provider)
    }

    private func wireLateWorldSystems(
        provider: any CellSceneProvider,
        renderer: Renderer,
        streamer: CellStreamer
    ) {
        wireCombat(provider: provider, renderer: renderer)
        // Package conditions observe the live quest, actor and reference state,
        // so selection advances after those runtimes in the same world tick.
        wirePackages(provider: provider, renderer: renderer)
        wirePerception(provider: provider, renderer: renderer)
        // Last (issue #205): the Talk candidate filter reads the death and
        // hostility state the combat and perception runtimes keep, so wiring it
        // earlier would hand the crosshair a list built before they existed.
        wireDialogue(provider: provider, streamer: streamer)
        // After everything (issue #427): the camera samples the speaker's head
        // bone and the movement runtime's own transform, both of which the
        // systems above produce in the same world tick.
        wireDialogueCamera(renderer: renderer)
    }

    /// View ray for use-key targeting, simulated-player modes only: the fly
    /// camera is a developer view and never picks up a target. Third person
    /// targets along the same view direction as first person; the eye it starts
    /// from is the orbit position, which is what the user is aiming with.
    private static func interactionRay(of renderer: Renderer) -> InteractionRay? {
        guard renderer.movementMode.isPlayerControlled else { return nil }
        return InteractionRay(
            origin: renderer.freeFlyCamera.position,
            direction: renderer.freeFlyCamera.forward
        )
    }

    /// Authoritative capsule pose for this frame's trigger-volume test
    /// (issue #173), gated on the simulated-player modes exactly as the
    /// interaction ray is.
    /// The streamer receives the eye position, so the feet position comes from
    /// the walk controller rather than being re-derived downstream.
    private static func playerCapsule(of renderer: Renderer) -> PlayerCapsuleState? {
        guard renderer.movementMode.isPlayerControlled else { return nil }
        return PlayerCapsuleState(
            capsule: renderer.walkController.capsule,
            feetPosition: renderer.walkController.feetPosition
        )
    }

    /// Runtime global variables (issue #165) and the game clock (issue #164).
    /// Weather-chance selection and the clock's per-frame TimeScale read both
    /// consume `GlobalResolution`, so every global write hands each a fresh
    /// resolution rather than rebuilding cells: a global changes a number, not
    /// a scene. Writes to the five clock-owned time globals redirect into the
    /// renderer's clock instead of storing an override (one source of truth;
    /// see docs/engine/game-clock.md).
    private func wireGlobals(provider: any CellSceneProvider, renderer: Renderer) {
        let worldState = worldState
        let globalStore = (provider as? GlobalDataProviding)?.globalStore
        self.globalStore = globalStore
        renderer.weather?.setGlobalResolution(
            worldState.globalResolution(defaults: globalStore), reroll: false
        )
        renderer.gameTime.globalResolution = worldState.globalResolution(defaults: globalStore)
        worldState.onTimeGlobalWrite = { [weak renderer] timeGlobal, value in
            guard let renderer else { return nil }
            let previous = renderer.gameClock.projectedValue(timeGlobal)
            renderer.gameTime.clock.setProjectedValue(value, for: timeGlobal)
            return previous
        }
        // Weak `self` breaks what would otherwise be a cycle through the store
        // this controller owns.
        worldState.onGlobalMutation = { [weak self, weak renderer] _ in
            guard let self, let renderer else { return }
            let resolution = self.worldState.globalResolution(defaults: globalStore)
            renderer.gameTime.globalResolution = resolution
            renderer.weather?.setGlobalResolution(resolution)
        }
    }

    /// World-audio directors are built lazily alongside the audio engine, so
    /// each callback remains a no-op until audio is enabled. Papyrus
    /// `OnActivate` subscribes beside this interaction handler through the
    /// same `CallbackFanOut`, and does not replace this engine event
    /// (issue #172).
    private func wireAudioCallbacks(_ controller: CellStreamer) {
        controller.onInteraction.add { [weak self] event in
            self?.soundDirector?.handleInteraction(event)
        }
        controller.onInteractionAnimation = { [weak self] event in
            self?.soundDirector?.handleInteractionAnimation(event)
        }
        controller.onAmbienceContextChanged = { [weak self] context in
            self?.soundDirector?.handleAmbienceContext(context)
        }
        controller.onMusicContextChanged = { [weak self] context in
            self?.musicDirector?.handleMusicContext(context)
        }
    }
}
