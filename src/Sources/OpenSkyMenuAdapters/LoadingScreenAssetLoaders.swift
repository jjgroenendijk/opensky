import OpenSkyFormatsESM
import OpenSkyFormatsMesh
public import OpenSkyGameData
import OpenSkyLoading
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyRendering
import OpenSkySessionInterface
import OpenSkyWorld

/// The file reads the loading screens start with the session: camera paths and model markers.
public struct LoadingScreenAssetLoaders {
    let game: any LoadingScreenWorldHost
    let state: LoadingScreenPartState
    let presentationRecords: PresentationRecordStore?

    /// Loads the camera paths the loading screens name, all of them started at once.
    public func cameraPathLoader() -> AssetLoader<String, LoadingCameraPath>? {
        guard let files = game.menuRecords?.scriptFileSystem else { return nil }
        let paths = AssetLoader<String, LoadingCameraPath> { path in
            try LoadingCameraPath(file: NIFFile(data: files.contents(forPath: "meshes\\" + path)))
        }
        let screens = presentationRecords?.loadScreens.records ?? []
        for path in Set(screens.compactMap(\.record.cameraPath)) {
            paths.prefetch(path)
        }
        return paths
    }

    /// Reads the inventory marker of every loading screen model, all of them started at once.
    func modelMarkerLoader() -> AssetLoader<String, LoadingModelMarker>? {
        guard
            let files = game.menuRecords?.scriptFileSystem,
            let store = presentationRecords else { return nil }
        let markers = AssetLoader<String, LoadingModelMarker> { path in
            let file = try NIFFile(data: files.contents(forPath: path))
            return LoadingModelMarker(rotation: file.inventoryMarker?.rotation)
        }
        let paths = store.loadScreens.records.compactMap(store.model(of:))
        for path in Set(paths.compactMap(InventoryItemPreview.meshPath)) {
            markers.prefetch(path)
        }
        return markers
    }

    func registerLoadingScreenCameraPaths(stage: SessionStage) {
        let gameSession = stage.gameSession
        guard let paths = cameraPathLoader() else { return }
        state.cameraPaths = paths
        gameSession.assetDrains.register(.loadingCameraPaths) { _ in paths.drain() }
        guard let markers = modelMarkerLoader() else { return }
        state.modelMarkers = markers
        gameSession.assetDrains.register(.loadingModelMarkers) { _ in markers.drain() }
    }
}
