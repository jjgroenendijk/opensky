// `VehicleWorldAdapter` joins the started session: what `wireVehicles` registered.

import Foundation
import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyTerrain
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// After the idles and packages, so a follower reads where its carrier ended up.
public struct VehiclesWiring {
    public init(_ adapter: VehicleWorldAdapter, gameSession: GameSession) {
        _ = VehicleWheelsWiring(adapter, gameSession: gameSession)
        gameSession.worldTick.register(.vehicles) { [weak adapter, weak gameSession] _ in
            guard let adapter else { return }
            adapter.run(adapter.vehicles.advance())
            // Only the end of a ride frees the seat; a chair holds the player too.
            let rides = adapter.vehicles.lastPoses[.player] != nil
            if adapter.ridesPlayer, !rides {
                gameSession?.playerSeat = nil
            }
            adapter.ridesPlayer = rides
        }
    }
}
