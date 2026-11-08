nonisolated public struct CachedAssetCounts: Equatable, Sendable {
    public var textures = 0
    public var models = 0

    public init(textures: Int = 0, models: Int = 0) {
        self.textures = textures
        self.models = models
    }
}
