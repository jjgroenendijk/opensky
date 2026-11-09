// `AIWorldAdapter` joins the started session: what `wirePackages` registered.

import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyNavigation
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgressionInterface
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
import simd

/// Connects `AIWorldAdapter` to the started session.
public struct AIPackagesWiring {
    public init(_ adapter: AIWorldAdapter, gameSession: GameSession) {
        let packages = adapter.game.packages
        guard packages.runtime != nil else { return }
        gameSession.worldTick.register(.packages) { [weak adapter, weak packages] delta in
            packages?.advance(by: Float(delta))
            adapter?.bumps.advanceBumps()
        }
    }
}
