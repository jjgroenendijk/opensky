// Models OpenSky makes at runtime, such as generated terrain LOD, cached under a key
// like a file's, so eviction and bounds treat them the same way.

import OpenSkyFormatsCore
import OpenSkyRenderCore
import OpenSkyRenderResources

nonisolated extension MeshLibrary {
    /// The cached model for `key`, or the one `make` builds, clipped like a terrain block.
    /// Nil when `make` has nothing to build.
    public func model(
        generatedKey key: String,
        terrainLODClipMask: TerrainLODClipMask?,
        make: () -> Model?
    ) throws -> RenderModel? {
        let pathKey = try meshKey(for: key)
        let cacheKey = cacheKey(path: pathKey, terrainLODClipMask: terrainLODClipMask)
        touchedKeys.insert(cacheKey)
        if let hit = cache[cacheKey] {
            textures.markTouched(modelTextureKeys[cacheKey] ?? [])
            return hit
        }
        guard let made = make() else { return nil }
        let model = terrainLODClipMask.map { TerrainLODClipper.clipped(made, to: $0) } ?? made
        guard !model.meshes.isEmpty else { return nil }
        let render = try makeRenderModel(model, key: cacheKey)
        cache[cacheKey] = render
        particleDefinitions[cacheKey] = []
        skippedShapes[cacheKey] = 0
        modelBounds[cacheKey] = ModelBounds.containing(model: model)
        return render
    }
}
