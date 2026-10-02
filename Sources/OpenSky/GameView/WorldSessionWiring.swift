// The composition root of a game session: builds the cell streamer and wires
// every system to it and to the renderer, in dependency order.

import OpenSkyFormatsCore
import OpenSkyMenus
import OpenSkyPerception
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import OSLog
import simd

final class WorldSessionWiring {
    unowned let game: GameViewController

    init(game: GameViewController) {
        self.game = game
    }

    /// Builds run off the main thread on the session's runner; the finished scene
    /// swaps in through `Renderer.setScene`. Every capture is weak, because
    /// `game` owns both the renderer and the streamer.
    func wireStreaming(session: CellSession, renderer: Renderer) {
        let provider = session.data
        let streamer = CellStreamer(
            center: CellCoordinate(x: FirstRenderCell.gridX, y: FirstRenderCell.gridY),
            runner: session.runner,
            sink: { [weak renderer] scene, camera in
                do {
                    try renderer?.setScene(scene, camera: camera)
                } catch {
                    GameViewController.logger.error(
                        "[ERROR] scene swap failed: \(String(describing: error), privacy: .public)"
                    )
                }
            }
        )
        game.aiWorld.wireAIOverlay(renderer: renderer, streamer: streamer)
        game.runtimeState.attach(globals: (provider as? GlobalDataProviding)?.globalStore)
        game.aiWorld.wireNPCMovement(renderer: renderer, streamer: streamer)
        streamer.bind(to: game.worldState)
        wireFrame(renderer: renderer, streamer: streamer)
        game.audioWorld.wireAudioCallbacks(streamer)
        // After the audio callbacks, so the engine's own interaction handling
        // stays first in the multicast order.
        game.scriptWorld.wirePapyrus(provider: provider, renderer: renderer, streamer: streamer)
        // Last in the multicast order: the activation sound and the recorded
        // activation both land before the item leaves the world.
        game.inventoryWorld.wireWorldItems(provider: provider, streamer: streamer)
        // After the item runtime, which owns the equipped set of the body.
        game.playerWorld.wirePlayerBody(provider: provider, renderer: renderer)
        // After `wirePapyrus`, whose `onWorldUpdate` closure these chain onto.
        wireActorSystems(provider: provider, renderer: renderer)
        // Melee, archery, then ragdolls: a fixed graph-event cursor order keeps
        // every runtime's trace reproducible.
        game.combatWorld.wireMelee(provider: provider, renderer: renderer)
        game.combatWorld.wireArchery(provider: provider, renderer: renderer)
        game.ragdollWorld.wireRagdoll(renderer: renderer)
        wireLateWorldSystems(provider: provider, renderer: renderer, streamer: streamer)
        renderer.terrainSampler = { [weak streamer] position in
            streamer?.sampleTerrain(at: position)
        }
        renderer.collisionQuery = { [weak streamer] bounds in
            streamer?.collisionCandidates(overlapping: bounds) ?? []
        }
        renderer.locomotion.sampleWater = { [weak streamer] position in
            streamer?.sampleWaterHeight(at: position)
        }
        game.streamer = streamer
    }

    private func wireFrame(renderer: Renderer, streamer: CellStreamer) {
        // Published inside the frame's own update, so the poses the pass uploads
        // are the ones this frame simulated.
        streamer.onDynamicPosesChanged = { [weak renderer] deltas in
            renderer?.dynamicInstanceDeltas = deltas
        }
        let input = game.cameraInput
        renderer.onFrame.add { [weak streamer, weak renderer, weak input] position in
            streamer?.update(
                cameraPosition: position,
                interactionRay: renderer.flatMap(Self.interactionRay(of:)),
                activate: input?.consumeActivation() ?? false,
                playerCapsule: renderer.flatMap(Self.playerCapsule(of:)),
                frameTime: renderer?.lastCameraDelta ?? 0
            )
        }
        // The center cell's regions feed region-weighted weather selection, on
        // the draw loop's thread.
        streamer.onCenterRegionsChanged = { [weak renderer] regions in
            renderer?.weather?.setRegions(regions)
        }
        streamer.onInteractionTargetChanged = { [weak game] target in
            game?.hud.updateTarget(game?.inventoryWorld.labelled(target))
        }
    }

    /// Magic effects write through the actor-value runtime, so it comes first.
    private func wireActorSystems(provider: any WorldDataProviding, renderer: Renderer) {
        game.actorWorld.wireActorValues(provider: provider, renderer: renderer)
        game.magicWorld.wireEffects(provider: provider, renderer: renderer)
        game.magicWorld.wireCasting(provider: provider, renderer: renderer)
        game.magicWorld.wireEnchantments(provider: provider)
        // After the cast loop, which folds spell cost through `Mod Spell Cost`.
        game.progressionWorld.wirePerks(provider: provider)
        // Memberships resolve through the actor-value template chain.
        game.factionWorld.wireFactions(provider: provider)
        game.inventoryWorld.wireVendors(provider: provider)
        game.progressionWorld.wireSkills(provider: provider)
        game.progressionWorld.wireProgression(provider: provider)
        // Ownership reads the FACT store, and the reporter joins the take path.
        game.crimeWorld.wireCrime(provider: provider)
    }

    private func wireLateWorldSystems(
        provider: any WorldDataProviding,
        renderer: Renderer,
        streamer: CellStreamer
    ) {
        // The loop reads what melee, archery, and the ragdolls did this frame.
        game.combatWorld.wireLoop(provider: provider, renderer: renderer)
        // Package conditions read the quest, actor, and reference state, so
        // selection advances after those runtimes.
        game.aiWorld.wirePackages(provider: provider, renderer: renderer)
        game.aiWorld.wirePerception(provider: provider, renderer: renderer)
        // The perception pass answers "did anybody see it" for every crime.
        game.crimeWorld.attachWitnesses(perception: game.perception.runtime)
        // The Talk filter reads the death and hostility state the systems above keep.
        game.dialogueWorld.wireDialogue(provider: provider, streamer: streamer)
        // The camera samples the speaker's head bone in the same world tick.
        game.dialogueWorld.wireDialogueCamera(renderer: renderer)
    }

    /// Player-controlled modes only: the fly camera never picks up a target.
    /// Third person aims along the view direction from the orbit position.
    private static func interactionRay(of renderer: Renderer) -> InteractionRay? {
        guard renderer.movementMode.isPlayerControlled else { return nil }
        return InteractionRay(
            origin: renderer.freeFlyCamera.position,
            direction: renderer.freeFlyCamera.forward
        )
    }

    /// The feet position comes from the walk controller, because the streamer
    /// receives only the eye position.
    private static func playerCapsule(of renderer: Renderer) -> PlayerCapsuleState? {
        guard renderer.movementMode.isPlayerControlled else { return nil }
        return PlayerCapsuleState(
            capsule: renderer.walkController.capsule,
            feetPosition: renderer.walkController.feetPosition
        )
    }
}
