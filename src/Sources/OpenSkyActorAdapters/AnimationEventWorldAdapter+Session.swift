// `AnimationEventWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

import OpenSkyActorPresentation
import OpenSkyCamera
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyObjectAnimation
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension AnimationEventWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(game: any AnimationEventWorldHost, stage: SessionStage?) {
        self.init(game: game)
        guard let stage else { return }
        registerAnimationEvent(stage: stage)
    }

    private func registerAnimationEvent(stage: SessionStage) {
        let gameSession = stage.gameSession
        let game = game
        gameSession.frameSteps.register(.animationEvents) { [weak gameSession, weak game] _ in
            guard let gameSession else { return }
            let idles = game?.idleWorld.idles
            let events = gameSession.animationEvents
            let locomotion = gameSession.locomotion
            let names = locomotion.graphEvents.drain(locomotion.animationEventConsumer)
                .map { idles?.ownGraphEvent($0, from: .player) ?? $0 }
            guard gameSession.movementMode.isPlayerControlled else { return }
            for name in names {
                events?.handle(name, from: .player)
            }
        }
    }
}
