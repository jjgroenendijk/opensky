// `DragonFlightWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyAIPackages
import OpenSkyBehavior
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension DragonFlightWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(
        game: some DragonFlightWorldHost & DragonFlightCandidatesHost,
        stage: SessionStage?
    ) {
        self.init(game: game)
        guard let stage else { return }
        registerDragonFlight(stage: stage)
    }

    private func registerDragonFlight(stage: SessionStage) {
        let gameSession = stage.gameSession
        gameSession.worldTick.register(.dragonFlight) { [weak self] delta in
            self?.game.dragonFlight.tick(deltaTime: delta)
        }
    }
}
