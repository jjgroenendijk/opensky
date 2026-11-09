// `LoadingScreenWorldAdapter` joins the started session: what `wireCameraPaths` registered.

import Foundation
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

/// The MOD2 camera meshes are small, and five serve every screen, so all are warmed.
public struct LoadingScreenCameraPathsWiring {
    public init(_ adapter: LoadingScreenWorldAdapter, gameSession: GameSession) {
        guard let files = adapter.game.worldData?.scriptFileSystem else { return }
        let paths = AssetLoader<String, NIFCameraTrack> { path in
            try NIFCameraTrack(file: NIFFile(data: files.contents(forPath: "meshes\\" + path)))
        }
        let screens = adapter.presentationRecords?.loadScreens.records ?? []
        for path in Set(screens.compactMap(\.record.cameraPath)) {
            paths.prefetch(path)
        }
        adapter.state.cameraPaths = paths
        gameSession.assetDrains.register(.loadingCameraPaths) { _ in paths.drain() }
    }
}
