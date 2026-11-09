// `LoadingScreenWorldAdapter` joins the started session: what `wire` registered.

import Foundation
public import OpenSkyCells
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyLoading
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
import OpenSkySessionInterface
import OpenSkyTerrain
public import OpenSkyWorld
import OpenSkyWorldInterface
import simd

/// Connects `LoadingScreenWorldAdapter` to the started session.
public struct LoadingScreenWiring {
    public init(
        _ adapter: LoadingScreenWorldAdapter,
        streamer: CellStreamer,
        gameSession: GameSession,
        bringFollowers: @escaping (CellScene) -> Void
    ) {
        streamer.onDoorTransitionStarted = { [weak adapter] in
            guard let adapter else { return }
            adapter.game.loadingScreens.begin(at: adapter.now)
        }
        streamer.onDoorTransitionFinished = { [weak adapter] scene in
            guard let adapter else { return }
            guard let scene else {
                adapter.game.loadingScreens.cancel()
                return
            }
            adapter.game.loadingScreens.destinationReady(
                location: adapter.location(of: scene.locationKey),
                at: adapter.now
            )
            bringFollowers(scene)
        }
        gameSession.frameSteps.register(.loadingScreen) { [weak adapter] _ in
            guard let adapter else { return }
            adapter.liftStartCoverIfReady()
            adapter.game.loadingScreens.tick(time: adapter.now)
            adapter.movie.tick()
        }
        _ = LoadingScreenCameraPathsWiring(adapter, gameSession: gameSession)
    }
}
