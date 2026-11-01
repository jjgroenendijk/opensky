// The size of a cell builder's asset caches, so a session can show whether
// eviction keeps up with the cells that leave.

nonisolated public struct CachedAssetCounts: Equatable, Sendable {
    public var textures = 0
    public var models = 0

    public init(textures: Int = 0, models: Int = 0) {
        self.textures = textures
        self.models = models
    }
}

/// A provider without libraries, such as a test fake, reports empty caches.
nonisolated extension CellSceneProvider {
    public var cachedAssetCounts: CachedAssetCounts {
        CachedAssetCounts()
    }
}
