// `AISeatingAdapter` joins the started session: what `wireFurniture` registered.

import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyCrimeInterface
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
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

/// After the vehicles, so the switch is set before a package sits.
public struct AIFurnitureWiring {
    public init(_ adapter: AISeatingAdapter, gameSession: GameSession) {
        gameSession.playerFurniture = adapter.owner
        let furniture = adapter.game.furniture
        let store = adapter.game.playerSettingsStore
        furniture.isEnabled = store.bool(.furniture)
        // The launcher page writes the switch while a session runs.
        store.observe { [weak furniture, weak store] id in
            guard id == .furniture, let store else { return }
            furniture?.isEnabled = store.bool(.furniture)
        }
        gameSession.worldTick.register(.furniture) { [weak owner = adapter.owner] _ in
            owner?.seating.releaseMovedPlayer()
            owner?.seating.game.furniture.advance()
        }
    }
}
