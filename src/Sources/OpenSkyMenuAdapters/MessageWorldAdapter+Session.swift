// `MessageWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

public import Foundation
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
        stage: SessionStage?,
        now: @escaping () -> Date
    ) {
        self.init(game: game, now: now)
        guard let stage else { return }
        registerMessage(stage: stage)
    }

    private func registerMessage(stage: SessionStage) {
        let gameSession = stage.gameSession
        cachedEditorIDs = nil
        // Frame steps run under a menu too, so notifications keep real time.
        gameSession.frameSteps.register(.messages) { [weak game = self.game, now] _ in
            game.map { Self.tick($0, now: now) }
        }
    }

    /// Notifications and subtitles keep real time, so they read the wall clock.
    public static func tick(_ game: any MessageWorldHost, now: () -> Date) {
        let time = now().timeIntervalSinceReferenceDate
        game.messages.tick(time: time)
        game.subtitles.advance(to: time)
    }
}
