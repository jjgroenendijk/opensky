// Streaming setup satellite for GameViewController. Split from
// GameViewController.swift to keep that file under the strict-lint size cap
// after the M9.2.2 ambience-context subscription landed here.

import OpenSkyFormatsCore
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import OSLog
import simd

extension GameViewController {
    /// Wires a streamer over the provider: builds run off-main on a serial
    /// runner, the recomposed scene swaps in via `Renderer.setScene`, and the
    /// renderer's per-frame hook drives the streamer with the live camera
    /// position. Weak captures both ways -> no retain cycle (this controller
    /// owns both renderer + streamer).
    func wireStreaming(session: CellSession, renderer: Renderer) {
        let provider = session.data
        let controller = CellStreamer(
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
        wireStreamingSources(provider: provider, renderer: renderer, streamer: controller)
        // Runtime world state. Every dispatched build snapshots the
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
        // , so a dropped bowl is where it rolled to after a save and
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
        audioWorld.wireAudioCallbacks(controller)
        // After the audio callbacks, so the engine's own interaction handling
        // stays first in the multicast order and Papyrus runs beside it.
        wirePapyrus(provider: provider, renderer: renderer, streamer: controller)
        // Last in the multicast order: the activation sound and
        // the recorded activation both land before the item leaves the world.
        inventoryWorld.wireWorldItems(provider: provider, streamer: controller)
        // After the item runtime, which owns the equipped set the body is
        // assembled from.
        wirePlayerBody(provider: provider, renderer: renderer)
        // After `wirePapyrus`, whose `onWorldUpdate` closure this chains onto
        // so both systems advance on the same simulated delta.
        wireActorSystems(provider: provider, renderer: renderer)
        combatWorld.wireMelee(provider: provider, renderer: renderer)
        // After melee, so the two runtimes register their graph-event cursors
        // in a fixed order and a trace read from either is reproducible.
        combatWorld.wireArchery(provider: provider, renderer: renderer)
        // After both, for the same reason: a fixed cursor-registration order
        // keeps every runtime's view of the graph event stream reproducible.
        wireRagdoll(renderer: renderer)
        // Last of the combat systems: the loop reads what melee, archery and
        // the ragdolls did this frame, so it has to advance after all three.
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
        provider: any WorldDataProviding,
        renderer: Renderer,
        streamer: CellStreamer
    ) {
        wireAIOverlay(renderer: renderer, streamer: streamer)
        wireGlobals(provider: provider, renderer: renderer)
        wireNPCMovement(renderer: renderer, streamer: streamer)
    }

    /// The two runtimes that own an actor's numbers, in the order they depend
    /// on each other: magic effects write through the actor-value surface, so
    /// the surface has to exist first.
    private func wireActorSystems(provider: any WorldDataProviding, renderer: Renderer) {
        actorWorld.wireActorValues(provider: provider, renderer: renderer)
        magicWorld.wireEffects(provider: provider, renderer: renderer)
        // A cast spends an actor value and applies effects through the effect
        // runtime, so both exist first.
        magicWorld.wireCasting(provider: provider, renderer: renderer)
        // The ENCH index only: an enchanted hit applies through the effect
        // runtime, and its charge lives in the world-state store.
        magicWorld.wireEnchantments(provider: provider)
        // After the cast loop, which takes the perk runtime by value so a spell
        // cost folds through the `Mod Spell Cost` entry point.
        progressionWorld.wirePerks(provider: provider)
        // Memberships resolve through the template chain the actor-value
        // baselines already indexed.
        factionWorld.wireFactions(provider: provider)
        inventoryWorld.wireVendors(provider: provider)
        // Writes through the actor-value runtime and reads the equipment runtime.
        progressionWorld.wireSkills(provider: provider)
        // Hands itself to the skill runtime and checks a perk spend against the
        // perk runtime and the AVIF trees.
        progressionWorld.wireProgression(provider: provider)
        // Ownership resolves against the FACT store the hostility derivation
        // uses, and the reporter joins the take path the world items built.
        crimeWorld.wireCrime(provider: provider)
    }

    private func wireLateWorldSystems(
        provider: any WorldDataProviding,
        renderer: Renderer,
        streamer: CellStreamer
    ) {
        combatWorld.wireLoop(provider: provider, renderer: renderer)
        // Package conditions observe the live quest, actor and reference state,
        // so selection advances after those runtimes in the same world tick.
        wirePackages(provider: provider, renderer: renderer)
        wirePerception(provider: provider, renderer: renderer)
        // Right after the perception pass, which is what answers "did anybody
        // see it" for every crime.
        crimeWorld.attachWitnesses(perception: perception.runtime)
        // Last: the Talk candidate filter reads the death and
        // hostility state the combat and perception runtimes keep, so wiring it
        // earlier would hand the crosshair a list built before they existed.
        dialogueWorld.wireDialogue(provider: provider, streamer: streamer)
        // After everything: the camera samples the speaker's head
        // bone and the movement runtime's own transform, both of which the
        // systems above produce in the same world tick.
        dialogueWorld.wireDialogueCamera(renderer: renderer)
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
    /// , gated on the simulated-player modes exactly as the
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

    /// A global write hands weather and the clock a fresh `GlobalResolution`
    /// rather than rebuilding cells. The five time globals write into the
    /// renderer's clock (docs/engine/game-clock.md).
    private func wireGlobals(provider: any WorldDataProviding, renderer: Renderer) {
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
}
