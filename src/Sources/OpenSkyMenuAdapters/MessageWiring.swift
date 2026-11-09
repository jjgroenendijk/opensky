// `MessageWorldAdapter` joins the started session: what `wire` registered.

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

/// Notifications and help records for the new session.
public struct MessageWiring {
    public init(_ adapter: MessageWorldAdapter, gameSession: GameSession) {
        adapter.cachedEditorIDs = nil
        adapter.game.messages.reloadHelpRecords()
        // Frame steps run under a menu too, so notifications keep real time.
        let messages = adapter.game.messages
        let subtitles = adapter.game.subtitles
        gameSession.frameSteps.register(.messages) { [weak messages, weak subtitles] _ in
            let now = Date().timeIntervalSinceReferenceDate
            messages?.tick(time: now)
            subtitles?.advance(to: now)
        }
    }
}
