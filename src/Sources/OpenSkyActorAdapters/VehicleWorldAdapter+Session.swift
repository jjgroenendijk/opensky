// `VehicleWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

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

extension VehicleWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(game: any VehicleWorldHost, stage: SessionStage?) {
        self.init(game: game)
        guard let stage else { return }
        registerVehicles(stage: stage)
    }

    private func registerVehicleWheels(stage: SessionStage) {
        let gameSession = stage.gameSession
        guard let files = game.worldData?.scriptFileSystem else {
            return
        }
        let wheels = AssetLoader<String, [SIMD2<Float>]> { path in
            try VehicleWheels.contacts(in: NIFFile(data: files.contents(forPath: path)))
        }
        self.wheels = wheels
        gameSession.assetDrains.register(.vehicleWheels) { _ in wheels.drain() }
    }

    private func registerVehicles(stage: SessionStage) {
        let gameSession = stage.gameSession
        registerVehicleWheels(stage: stage)
        gameSession.worldTick.register(.vehicles) { [weak self, weak gameSession] _ in
            guard let self else { return }
            run(vehicles.advance())
            // Only the end of a ride frees the seat; a chair holds the player too.
            let rides = vehicles.lastPoses[.player] != nil
            if ridesPlayer, !rides {
                gameSession?.playerSeat = nil
            }
            ridesPlayer = rides
        }
    }
}
