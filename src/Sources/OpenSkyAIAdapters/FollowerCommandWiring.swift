// `FollowerCommandWorldAdapter` joins the started session: what `wire` registered.

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

/// Connects `FollowerCommandWorldAdapter` to the started session.
public struct FollowerCommandWiring {
    public init(_ adapter: FollowerCommandWorldAdapter, gameSession: GameSession) {
        let commands = adapter.game.followerCommands
        gameSession.worldTick.register(.followerCommands) { [weak commands] delta in
            commands?.tick(delta)
        }
    }
}
