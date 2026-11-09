// `AISeatingAdapter` joins the started session: what `wireFurniture` registered.

import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// After the vehicles, so the switch is set before a package sits.
public struct AIFurnitureWiring {
    public init(_ adapter: AIWorldAdapter, gameSession: GameSession) {
        gameSession.playerFurniture = adapter
        let furniture = adapter.seating.game.furniture
        let store = adapter.seating.game.playerSettingsStore
        furniture.isEnabled = store.bool(.furniture)
        // The launcher page writes the switch while a session runs.
        store.observe { [weak furniture, weak store] id in
            guard id == .furniture, let store else { return }
            furniture?.isEnabled = store.bool(.furniture)
        }
        gameSession.worldTick.register(.furniture) { [weak adapter] _ in
            adapter?.seating.releaseMovedPlayer()
            adapter?.seating.game.furniture.advance()
        }
    }
}
