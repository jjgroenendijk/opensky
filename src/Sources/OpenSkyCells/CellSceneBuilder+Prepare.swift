// Builds the cell builder's first-use indexes before the first cell asks for them,
// so the world load pays for them while its other stores build, not the first arrival.

import OpenSkyFormatsCore

nonisolated extension CellSceneBuilder {
    /// Every load-order index a cell build reads. With `worldspace`, also that
    /// worldspace's cell lookups and its terrain LOD brightness.
    public func prepareIndexes(worldspace: String?) {
        _ = loadOrderIndexBuildingIfNeeded()
        _ = statIndexBuildingIfNeeded()
        _ = textureSetIndexBuildingIfNeeded()
        _ = modelBaseIndexBuildingIfNeeded()
        _ = materialTypeIndexBuildingIfNeeded()
        _ = lightingTemplateIndexBuildingIfNeeded()
        _ = lightIndexBuildingIfNeeded()
        _ = landTextureIndexBuildingIfNeeded()
        _ = grassIndexBuildingIfNeeded()
        _ = addOnModelIndexBuildingIfNeeded()
        _ = worldspaceIndexBuildingIfNeeded()
        _ = waterTypeIndexBuildingIfNeeded()
        _ = actorResolversBuildingIfNeeded()
        guard
            let worldspace,
            let world = attempt({
                try worldChildrenGroup(
                    editorID: worldspace,
                    localized: pluginLocalized
                )
            })
        else { return }
        _ = findCell(in: world, gridX: 0, gridY: 0, localized: pluginLocalized)
        _ = persistentParentPool(in: world, localized: pluginLocalized)
        _ = terrainLODBrightness(lodWorldspace: lodWorldspace(of: worldspace))
    }
}
