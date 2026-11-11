// Builds the cell builder's first-use indexes before the first cell asks for them,
// so the world load pays for them while its other stores build, not the first arrival.

import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated extension CellSceneBuilder {
    /// Every load-order index a cell build reads. With `worldspace`, also that
    /// worldspace's cell lookups and its terrain LOD brightness.
    public func prepareIndexes(worldspace: String?) {
        _ = interiorBuilder.loadOrderIndexBuildingIfNeeded()
        _ = recordIndex.statIndexBuildingIfNeeded()
        _ = recordIndex.textureSetIndexBuildingIfNeeded()
        _ = recordIndex.modelBaseIndexBuildingIfNeeded()
        _ = recordIndex.materialTypeIndexBuildingIfNeeded()
        _ = interiorBuilder.lightingTemplateIndexBuildingIfNeeded()
        _ = interiorBuilder.lightIndexBuildingIfNeeded()
        _ = terrainBuilder.landTextureIndexBuildingIfNeeded()
        _ = terrainBuilder.grassIndexBuildingIfNeeded()
        _ = objectBuilder.addOnModelIndexBuildingIfNeeded()
        _ = waterBuilder.worldspaceIndexBuildingIfNeeded()
        _ = waterBuilder.waterTypeIndexBuildingIfNeeded()
        _ = actorBuilder.actorResolversBuildingIfNeeded()
        guard
            let worldspace,
            let world = attempt({
                try worldChildrenGroup(
                    editorID: worldspace,
                    localized: pluginLocalized
                )
            })
        else { return }
        _ = recordIndex.findCell(in: world, gridX: 0, gridY: 0, localized: pluginLocalized)
        _ = interiorBuilder.persistentParentPool(in: world, localized: pluginLocalized)
        _ = terrainBuilder
            .terrainLODBrightness(lodWorldspace: terrainBuilder.lodWorldspace(of: worldspace))
    }

    /// The winning WRLD with that editor ID in the whole load order, and the
    /// first plugin's children group for it.
    nonisolated func uncachedWorldChildrenGroup(
        editorID: String,
        localized _: Bool
    ) throws -> FoundWorld {
        guard
            let match = waterBuilder.worldspaceIndexBuildingIfNeeded()
                .filter({ $0.value.editorID == editorID })
                .min(by: { $0.key < $1.key })
        else { throw CellSceneError.worldspaceNotFound(editorID: editorID) }
        let formID = FormID(stored: match.key)
        return FoundWorld(
            children: recordIndex.baseWorldChildren(of: formID), worldspace: match.value,
            formID: formID
        )
    }
}
