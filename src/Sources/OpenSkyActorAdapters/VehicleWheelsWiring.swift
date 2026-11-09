// `VehicleWorldAdapter` joins the started session: what `wireWheels` registered.

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
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyTerrain
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// Connects `VehicleWorldAdapter` to the started session.
public struct VehicleWheelsWiring {
    public init(_ adapter: VehicleWorldAdapter, gameSession: GameSession) {
        guard let files = adapter.game.worldData?.scriptFileSystem else {
            return
        }
        let wheels = AssetLoader<String, [SIMD2<Float>]> { path in
            try VehicleWheels.contacts(in: NIFFile(data: files.contents(forPath: path)))
        }
        adapter.wheels = wheels
        gameSession.assetDrains.register(.vehicleWheels) { _ in wheels.drain() }
    }
}
