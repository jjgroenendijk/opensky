// The pipeline cache the player settings ask for. Its archive lives in the asset cache
// folder, so the one folder setting places both caches.

public import Foundation
public import Metal
import OpenSkyAssetCache
import OpenSkyFormatsCore
public import OpenSkyGameData
public import OpenSkyRenderResources

extension PipelineCache {
    /// A cache with an archive file when the setting is on, else one that only compiles.
    public static func fromSettings(device: any MTLDevice, store: PlayerSettingsStore) throws
        -> PipelineCache
    {
        try PipelineCache(device: device, fileURL: archiveURL(device: device, store: store))
    }

    static func archiveURL(device: any MTLDevice, store: PlayerSettingsStore) -> URL? {
        guard
            store.bool(.pipelineCacheEnabled),
            let folder = archiveFolder(store: store)
        else { return nil }
        return PipelineCacheFolder.archiveURL(inCacheFolder: folder, device: device)
    }

    /// The folder that holds the archives, whether or not the cache is on.
    public static func archiveFolder(store: PlayerSettingsStore) -> URL? {
        attempt { try AssetCacheSettings(store: store).effectiveFolder() }
            .map(PipelineCacheFolder.folder(inCacheFolder:))
    }
}
