// Builds the cell builder's first-use indexes before the first cell asks for them,
// so the world load pays for them while its other stores build, not the first arrival.

import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated extension CellSceneBuilder.CellIndexPreparation {
    /// Every load-order index a cell build reads. With `worldspace`, also that
    /// worldspace's cell lookups and its terrain LOD brightness.
    func prepareIndexes(worldspace: String?) {
        _ = owner.recordIndex.loadOrderIndexBuildingIfNeeded()
        _ = owner.modelIndex.statIndexBuildingIfNeeded()
        _ = owner.modelIndex.textureSetIndexBuildingIfNeeded()
        _ = owner.modelIndex.modelBaseIndexBuildingIfNeeded()
        _ = owner.modelIndex.materialTypeIndexBuildingIfNeeded()
        _ = owner.interiorLighting.lightingTemplateIndexBuildingIfNeeded()
        _ = owner.interiorLighting.lightIndexBuildingIfNeeded()
        _ = owner.terrainBuilder.grass.landTextureIndexBuildingIfNeeded()
        _ = owner.terrainBuilder.grass.grassIndexBuildingIfNeeded()
        _ = owner.objectBuilder.addOnModelIndexBuildingIfNeeded()
        _ = owner.waterBuilder.worldspaceIndexBuildingIfNeeded()
        _ = owner.waterBuilder.waterTypeIndexBuildingIfNeeded()
        _ = owner.actorBuilder.resolver.actorResolversBuildingIfNeeded()
        guard
            let worldspace,
            let world = attempt({
                try owner.records.worldChildrenGroup(
                    editorID: worldspace,
                    localized: owner.pluginLocalized
                )
            })
        else { return }
        _ = owner.recordIndex.findCell(
            in: world,
            gridX: 0,
            gridY: 0,
            localized: owner.pluginLocalized
        )
        _ = owner.doorTransitions.persistentParentPool(in: world, localized: owner.pluginLocalized)
        _ = owner.terrainBuilder
            .terrainLOD.terrainLODBrightness(lodWorldspace: owner.terrainBuilder.distantLOD
                .lodWorldspace(of: worldspace))
    }

    /// The winning WRLD with that editor ID in the whole load order, and the
    /// first plugin's children group for it.
    nonisolated func uncachedWorldChildrenGroup(
        editorID: String,
        localized _: Bool
    ) throws -> FoundWorld {
        guard
            let match = owner.waterBuilder.worldspaceIndexBuildingIfNeeded()
                .filter({ $0.value.editorID == editorID })
                .min(by: { $0.key < $1.key })
        else { throw CellSceneError.worldspaceNotFound(editorID: editorID) }
        let formID = FormID(stored: match.key)
        return FoundWorld(
            children: owner.recordIndex.baseWorldChildren(of: formID), worldspace: match.value,
            formID: formID
        )
    }
}
