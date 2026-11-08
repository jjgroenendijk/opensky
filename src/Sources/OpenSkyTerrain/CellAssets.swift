/// The mesh and texture keys one cell touched. Streaming keeps the union over
/// resident cells on unload (docs/engine/cell-streaming.md).
nonisolated public struct CellAssets: Equatable, Sendable {
    public var meshKeys: Set<String> = []
    public var textureKeys: Set<String> = []

    public init(meshKeys: Set<String> = [], textureKeys: Set<String> = []) {
        self.meshKeys = meshKeys
        self.textureKeys = textureKeys
    }
}
