// `IdleWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyBehavior
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyNavigation
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension IdleWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(game: some IdleWorldHost & IdlePlacementHost, stage: SessionStage?) {
        self.init(game: game)
        guard let stage else { return }
        registerIdles(stage: stage)
    }

    private func registerIdles(stage: SessionStage) {
        let gameSession = stage.gameSession
        gameSession.worldTick.register(.idles) { [weak self] _ in
            guard let idles = self?.idles, idles.store != nil else { return }
            idles.advance()
        }
    }
}
