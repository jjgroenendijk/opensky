// `EffectGraphWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

import OpenSkyActorPresentation
import OpenSkyBehavior
import OpenSkyCombatInterface
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyObjectAnimation
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface

extension EffectGraphWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(game: any EffectGraphWorldHost, stage: SessionStage?) {
        self.init(game: game)
        guard let stage else { return }
        registerEffectGraph(stage: stage)
    }

    private func registerEffectGraph(stage: SessionStage) {
        let gameSession = stage.gameSession
        guard game.audioFileSystem != nil else { return }
        gameSession.worldTick.register(.effectGraphs) { [weak self] delta in
            self?.game.effectGraphs.tick(deltaTime: delta)
        }
    }
}
