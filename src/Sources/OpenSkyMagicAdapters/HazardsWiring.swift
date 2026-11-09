// `HazardWorldAdapter` joins the started session: what `wireHazards` registered.

import Foundation
public import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface

/// Connects `HazardWorldAdapter` to the started session.
public struct HazardsWiring {
    public init(
        _ adapter: HazardWorldAdapter,
        provider: WorldDataStores,
        streamer: CellStreamer,
        gameSession: GameSession
    ) {
        adapter.store = provider.lockTrapData.hazards
        streamer.cellHazards.register(.hazards) { [weak adapter] event in
            adapter?.load(event)
        }
        gameSession.frameSteps.register(.hazards) { [weak adapter, weak gameSession] _ in
            adapter?.tick(paused: gameSession?.worldSimPaused ?? true)
        }
    }
}
