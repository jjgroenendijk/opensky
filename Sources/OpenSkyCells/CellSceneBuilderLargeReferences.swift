// Large references past the loaded grid: the WRLD `RNAM` lists them per cell, and the
// distant LOD ring draws them with their full model (docs/engine/distant-lod.md).

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyRendering
import OpenSkyTerrain

nonisolated extension CellSceneBuilder {
    /// The ring's large references, placed as their cells place them. A reference
    /// the plugin disables at the start stays hidden, as in its own cell.
    nonisolated func largeReferencePlacements(
        worldspaceEditorID: String,
        cells: Set<CellCoordinate>
    ) -> [RenderPlacement] {
        let listed = largeReferences(worldspaceEditorID: worldspaceEditorID, cells: cells)
        var counts = BuildCounts()
        var references: [PlacedReference] = []
        for (cell, wanted) in listed.sorted(by: { ($0.key.x, $0.key.y) < ($1.key.x, $1.key.y) }) {
            guard
                let source = try? exteriorBuildSource(
                    worldspaceEditorID: worldspaceEditorID, gridX: cell.x, gridY: cell.y
                )
            else { continue }
            let collected = collectTaggedReferences(in: source.cell, counts: &counts)
            let placed = exteriorReferences(
                local: collected.map(\.reference), world: source.world,
                coordinate: cell, localized: pluginLocalized
            )
            references += placed.filter {
                wanted.contains($0.formID.rawValue) && !$0.isInitiallyDisabled
            }
        }
        return resolveInstances(refs: references, counts: &counts)
            .filter { !$0.model.meshes.isEmpty }
            .map { instance in
                RenderPlacement(
                    model: instance.model,
                    transform: instance.transform,
                    bounds: meshes.bounds(forPath: instance.modelPath, surface: instance.surface)?
                        .transformed(by: instance.transform)
                )
            }
    }

    /// `RNAM` FormIDs by the cell each reference sits in, kept to `cells`.
    nonisolated private func largeReferences(
        worldspaceEditorID: String,
        cells: Set<CellCoordinate>
    ) -> [CellCoordinate: Set<UInt32>] {
        guard
            !cells.isEmpty,
            let world = worldspaceIndexBuildingIfNeeded().values
                .first(where: { $0.editorID == worldspaceEditorID })
        else { return [:] }
        var listed: [CellCoordinate: Set<UInt32>] = [:]
        for entry in world.details.largeReferences {
            for reference in entry.references {
                let cell = CellCoordinate(
                    x: Int32(reference.cell.x), y: Int32(reference.cell.y)
                )
                if cells.contains(cell) {
                    listed[cell, default: []].insert(reference.reference.rawValue)
                }
            }
        }
        return listed
    }
}
