// `RagdollWorldAdapter` joins the started session: what `wireRagdoll` registered.

import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyCrimeInterface
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// A world-tick step, so the ragdolls see the same simulated
/// delta as the other systems, and a menu-paused frame stops a falling
/// corpse. The pose reaches the scene on the drawn frame, so a paused
/// corpse stays where it was.
public struct RagdollWiring {
    public init(_ adapter: RagdollWorldAdapter, gameSession: GameSession) {
        let ragdoll = adapter.game.ragdoll
        let worldTick = gameSession.worldTick
        worldTick.register(.ragdoll) { [weak adapter, weak ragdoll, weak gameSession] delta in
            guard let ragdoll, let gameSession else { return }
            let locomotion = gameSession.locomotion
            adapter?.run(ragdoll.advance(
                events: locomotion.graphEvents.drain(locomotion.ragdollEventConsumer),
                controls: locomotion.ragdollGraphControls,
                delta: delta
            ))
            adapter?.playerFall.advancePlayerDeath(delta: delta)
            if let streamer = adapter?.game.streamer {
                ragdoll.runtime?.solveLinks(to: &streamer.dynamicBodies, frameTime: delta)
            }
        }
        gameSession.frameSteps.register(.ragdoll) { [weak adapter, weak ragdoll] _ in
            adapter?.run(ragdoll?.publishPoses() ?? [])
        }
    }
}
