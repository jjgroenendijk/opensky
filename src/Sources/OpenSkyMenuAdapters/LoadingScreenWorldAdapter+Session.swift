// `LoadingScreenWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

public import Foundation
import OpenSkyCells
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

extension LoadingScreenWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(
        game: some LoadingScreenWorldHost & LoadingScreenPresentationHost,
        stage: SessionStage?,
        clock: @escaping () -> Date
    ) {
        self.init(game: game, clock: clock)
        guard let stage else { return }
        registerLoadingScreen(stage: stage)
    }

    public var assetLoaders: LoadingScreenAssetLoaders {
        LoadingScreenAssetLoaders(game: game, presentationRecords: presentationRecords)
    }

    private func registerLoadingScreenCameraPaths(stage: SessionStage) {
        let gameSession = stage.gameSession
        guard let paths = assetLoaders.cameraPathLoader() else { return }
        state.cameraPaths = paths
        gameSession.assetDrains.register(.loadingCameraPaths) { _ in paths.drain() }
        guard let markers = assetLoaders.modelMarkerLoader() else { return }
        state.modelMarkers = markers
        gameSession.assetDrains.register(.loadingModelMarkers) { _ in markers.drain() }
    }

    private func registerLoadingScreen(stage: SessionStage) {
        let streamer = stage.streamer
        let gameSession = stage.gameSession
        streamer.onDoorTransitionStarted = { [weak self] fade in
            guard let self else { return }
            game.loadingScreens.begin(at: now, fadeSeconds: fade.seconds, fadeWait: fade.wait)
        }
        streamer.onDoorTransitionFinished = { [weak self] scene in
            guard let self else { return }
            guard let scene else {
                game.loadingScreens.cancel()
                return
            }
            game.loadingScreens.destinationReady(
                location: location(of: scene.locationKey),
                at: now
            )
            state.bringFollowers?(scene)
        }
        gameSession.frameSteps.register(.loadingScreen) { [weak self] _ in
            guard let self else { return }
            liftStartCoverIfReady()
            game.loadingScreens.tick(time: now)
            movie.tick(now: now)
        }
        registerLoadingScreenCameraPaths(stage: stage)
    }
}
