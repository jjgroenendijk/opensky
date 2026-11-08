// `FollowerCommandWorldAdapter` joins the started session: what `wire` registered.

import OpenSkyActors
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCrime
import OpenSkyCrimeInterface
import OpenSkyDialogue
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScripting
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
