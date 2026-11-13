// `ActorGraphWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyAudio
import OpenSkyBehavior
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension ActorGraphWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(
        game: some ActorGraphWorldHost & ActorGraphGraphEventsHost,
        stage: SessionStage?
    ) {
        self.init(game: game)
        guard let stage else { return }
        registerActorGraph(stage: stage)
    }

    private func registerActorGraph(stage: SessionStage) {
        let gameSession = stage.gameSession
        guard game.audioFileSystem != nil else { return }
        gameSession
            .audio.actorSoundSources = { [weak self] in
                self?.graphEvents.actorSoundSources() ?? []
            }
        gameSession.worldTick.register(.actorGraphs) { [weak self] delta in
            self?.graphs.tick(deltaTime: delta)
        }
    }
}
