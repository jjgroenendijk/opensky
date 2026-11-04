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
        return largeReferenceIndex(world: world.formID.rawValue).filter { cells.contains($0.key) }
    }

    /// Each plugin's `WRLD` lists only the large references it adds, so the lists of
    /// every plugin are joined, as `RNAM` counts on the install show.
    nonisolated private func largeReferenceIndex(world: UInt32) -> [CellCoordinate: Set<UInt32>] {
        if let cached = largeReferenceIndex[world] {
            return cached
        }
        var skipped = SkippedRecords()
        let versions = loadOrderIndexBuildingIfNeeded().loadOrder.decodeEveryVersion(
            of: "WRLD", skipped: &skipped,
            using: WorldspaceLargeReferenceCell.decodeAll(record:)
        )
        var index: [CellCoordinate: Set<UInt32>] = [:]
        for entry in (versions[world] ?? []).joined() {
            for reference in entry.references {
                let cell = CellCoordinate(x: Int32(reference.cell.x), y: Int32(reference.cell.y))
                index[cell, default: []].insert(reference.reference.rawValue)
            }
        }
        largeReferenceIndex[world] = index
        return index
    }
}
