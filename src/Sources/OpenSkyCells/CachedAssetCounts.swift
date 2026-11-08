public import OpenSkyWorldInterface

// The size of a cell builder's asset caches, so a session can show whether
// eviction keeps up with the cells that leave.

/// A provider without libraries, such as a test fake, reports empty caches.
nonisolated extension CellSceneProvider {
    public var cachedAssetCounts: CachedAssetCounts {
        CachedAssetCounts()
    }
}
