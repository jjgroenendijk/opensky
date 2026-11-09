// `IdleWorldAdapter` joins the started session: what `wireIdles` registered.

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

/// After packages, because the pass reads each actor's current procedure.
public struct IdlesWiring {
    public init(_ adapter: IdleWorldAdapter, gameSession: GameSession) {
        let idles = adapter.idles
        guard idles.store != nil else { return }
        gameSession.worldTick.register(.idles) { [weak idles] _ in
            idles?.advance()
        }
    }
}
