// `MagicWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

import OpenSkyActorsInterface
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

extension MagicWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(
        game: some MagicWorldHosts,
        stage: SessionStage?
    ) {
        self.init(game: game)
        guard let stage else { return }
        registerMagic(stage: stage)
    }

    private func registerMagic(stage: SessionStage) {
        let gameSession = stage.gameSession
        frames.registerEffects(gameSession: gameSession)
        frames.registerCasting(gameSession: gameSession)
    }
}
