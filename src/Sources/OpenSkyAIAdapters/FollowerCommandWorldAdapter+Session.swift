// `FollowerCommandWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension FollowerCommandWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(
        game: some FollowerCommandWorldHost & FollowerCommandTasksHost,
        stage: SessionStage?
    ) {
        self.init(game: game)
        guard let stage else { return }
        registerFollowerCommand(stage: stage)
    }

    private func registerFollowerCommand(stage: SessionStage) {
        let gameSession = stage.gameSession
        gameSession.worldTick.register(.followerCommands) { [weak game = self.game] delta in
            game?.followerCommands.tick(delta)
        }
    }
}
