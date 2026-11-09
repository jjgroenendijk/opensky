// `EffectsWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension EffectsWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(
        game: some EffectsWorldHost & EffectsBodyImpulsesHost & EffectsTrapControlHost &
            EffectsBlastsHost & EffectsEffectPlacementHost & EffectsLocatorHost,
        stage: SessionStage?
    ) {
        self.init(game: game)
        guard let stage else { return }
        registerEffects(stage: stage)
    }

    private func registerEffects(stage: SessionStage) {
        let provider = stage.data
        let streamer = stage.streamer
        let gameSession = stage.gameSession
        guard let records = provider.effectRecords else { return }
        gameSession.imageSpaceLinks = ImageSpaceLinks(
            records: records, weatherPlugin: EffectsBasePlugin.name
        )
        let frameSteps = gameSession.frameSteps
        frameSteps.register(.effects) { [weak self, weak gameSession, weak streamer] position in
            guard let self, let gameSession else { return }
            state.cameraPosition = position
            tick(gameSession: gameSession, streamer: streamer)
            let now = ProcessInfo.processInfo.systemUptime
            let delta = Float(now - (state.lastImpulseStep ?? now))
            state.lastImpulseStep = now
            if gameSession.movementMode.isPlayerControlled {
                game.combat.impulses?.advance(deltaTime: delta)
            }
        }
    }
}
