// The pipeline cache the player settings ask for. Its archive lives in the asset cache
// folder, so the one folder setting places both caches.

public import Foundation
import OpenSkyAssetCache
import OpenSkyFormatsCore
public import OpenSkyGameData
public import OpenSkyRenderResources

extension PipelineCache {
    /// The archive file when the setting is on, else nil, so the cache only compiles.
    /// `shaderLibrary` is the compiled library file, which the archive name stamps.
    public static func archiveURL(
        gpuName: String, store: PlayerSettingsStore, shaderLibrary: URL?
    ) -> URL? {
        guard
            store.bool(.pipelineCacheEnabled),
            let folder = archiveFolder(store: store)
        else { return nil }
        return PipelineCacheFolder.archiveURL(
            inCacheFolder: folder, gpuName: gpuName, shaderLibrary: shaderLibrary
        )
    }

    /// The folder that holds the archives, whether or not the cache is on.
    public static func archiveFolder(store: PlayerSettingsStore) -> URL? {
        attempt { try AssetCacheSettings(store: store).effectiveFolder() }
            .map(PipelineCacheFolder.folder(inCacheFolder:))
    }
}
