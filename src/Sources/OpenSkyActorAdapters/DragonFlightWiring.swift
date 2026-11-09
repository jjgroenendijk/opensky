// `DragonFlightWorldAdapter` joins the started session: what `wire` registered.

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

/// Connects `DragonFlightWorldAdapter` to the started session.
public struct DragonFlightWiring {
    public init(_ adapter: DragonFlightWorldAdapter, gameSession: GameSession) {
        gameSession.worldTick.register(.dragonFlight) { [weak adapter] delta in
            adapter?.game.dragonFlight.tick(deltaTime: delta)
        }
    }
}
