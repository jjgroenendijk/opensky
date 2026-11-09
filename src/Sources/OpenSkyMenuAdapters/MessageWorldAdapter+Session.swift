// `MessageWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

import Foundation
import OpenSkyAudio
import OpenSkyCamera
import OpenSkyCells
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

extension MessageWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(
        game: some MessageWorldHost & MessageCameraEffectsHost,
        stage: SessionStage?
    ) {
        self.init(game: game)
        guard let stage else { return }
        registerMessage(stage: stage)
    }

    private func registerMessage(stage: SessionStage) {
        let gameSession = stage.gameSession
        cachedEditorIDs = nil
        // Frame steps run under a menu too, so notifications keep real time.
        gameSession.frameSteps.register(.messages) { [weak game = self.game] _ in
            let now = Date().timeIntervalSinceReferenceDate
            game?.messages.tick(time: now)
            game?.subtitles.advance(to: now)
        }
    }
}
