// The first distant ring, built beside the near grid at session start. It uses
// its own mesh and texture libraries, so it never touches the caches the cell
// build queue owns (docs/engine/distant-lod.md, "Start").

import Foundation
import Metal
import OpenSkyAssetCache
import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkyRendering

nonisolated public struct DistantLODPrebuild: Sendable {
    public let fileSystem: any GameFileSource
    public let device: any MTLDevice
    public let cache: AssetCacheReader?
    public let configurationStore: TerrainLODConfigurationStore
    public let worldspace: String

    public init(
        fileSystem: any GameFileSource,
        device: any MTLDevice,
        cache: AssetCacheReader?,
        configurationStore: TerrainLODConfigurationStore,
        worldspace: String
    ) {
        self.fileSystem = fileSystem
        self.device = device
        self.cache = cache
        self.configurationStore = configurationStore
        self.worldspace = worldspace
    }

    @concurrent
    public func build(
        center: CellCoordinate,
        hiddenCells: Set<CellCoordinate>
    ) async -> Result<DistantLODScene?, any Error> {
        Result {
            let textures = try TextureLibrary(fileSystem: fileSystem, device: device)
            textures.assetCache = cache
            let meshes = MeshLibrary(fileSystem: fileSystem, device: device, textures: textures)
            meshes.assetCache = cache
            return try DistantLODBuilder(
                fileSystem: fileSystem,
                meshes: meshes,
                textures: textures,
                configurationStore: configurationStore
            ).build(worldspace: worldspace, center: center, hiddenCells: hiddenCells)
        }
    }
}
