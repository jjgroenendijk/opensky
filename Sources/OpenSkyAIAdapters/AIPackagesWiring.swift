// `AIWorldAdapter` joins the started session: what `wirePackages` registered.

import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyDiagnostics
import OpenSkyDialogue
import OpenSkyFactions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMagic
import OpenSkyNavigation
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
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
