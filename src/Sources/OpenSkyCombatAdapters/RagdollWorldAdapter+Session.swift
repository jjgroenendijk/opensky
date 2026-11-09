// `RagdollWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

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

extension RagdollWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(
        game: some RagdollWorldHost & RagdollRecoveryHost & RagdollRemainsHost &
            RagdollPlayerFallHost & RagdollPoseReadsHost & RagdollDeathsHost,
        stage: SessionStage?
    ) {
        self.init(game: game)
        guard let stage else { return }
        registerRagdoll(stage: stage)
    }

    private func registerRagdoll(stage: SessionStage) {
        let gameSession = stage.gameSession
        let worldTick = gameSession.worldTick
        worldTick.register(.ragdoll) { [weak self, weak gameSession] delta in
            guard let ragdoll = self?.game.ragdoll, let gameSession else { return }
            let locomotion = gameSession.locomotion
            self?.run(ragdoll.advance(
                events: locomotion.graphEvents.drain(locomotion.ragdollEventConsumer),
                controls: locomotion.ragdollGraphControls,
                delta: delta
            ))
            self?.playerFall.advancePlayerDeath(delta: delta)
            if let streamer = self?.game.streamer {
                ragdoll.runtime?.solveLinks(to: &streamer.dynamicBodies, frameTime: delta)
            }
        }
        gameSession.frameSteps.register(.ragdoll) { [weak self] _ in
            guard let self else { return }
            run(game.ragdoll.publishPoses())
        }
    }
}
