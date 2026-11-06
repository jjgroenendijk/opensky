// Large references and Is Full LOD references past the loaded grid: the distant LOD ring
// draws them with their full model, in their enable state (docs/engine/distant-lod.md).

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyRendering
import OpenSkyTerrain
import OpenSkyWorldState

/// References the distant ring draws with their full model, and the object IDs whose
/// enable change must rebuild the ring: each candidate and its enable parent.
nonisolated public struct DistantReferences: Sendable {
    public var placements: [RenderPlacement] = []
    public var watchedObjectIDs: Set<UInt32> = []

    mutating func watch(_ references: [PlacedReference]) {
        for reference in references {
            watchedObjectIDs.insert(reference.formID.objectID)
            if let parent = reference.enableParent?.parent {
                watchedObjectIDs.insert(parent.objectID)
            }
        }
    }
}

nonisolated extension CellSceneBuilder {
    /// The ring's large references, placed as their cells place them, in the enable state
    /// `state` and their enable parents give, as in their own cells.
    nonisolated func largeReferencePlacements(
        worldspaceEditorID: String,
        cells: Set<CellCoordinate>,
        state: WorldStateSnapshot = .empty
    ) -> DistantReferences {
        let listed = largeReferences(worldspaceEditorID: worldspaceEditorID, cells: cells)
        var counts = BuildCounts()
        var references: [PlacedReference] = []
        var result = DistantReferences()
        let deltas = state.deltasByKey()
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
            ).filter { wanted.contains($0.formID.rawValue) }
            result.watch(placed)
            references += applyRuntimeState(
                refs: placed,
                entries: referenceEntries(refs: placed, collected: collected),
                deltas: deltas,
                parentPool: persistentParentPool(in: source.world, localized: pluginLocalized),
                counts: &counts
            )
        }
        result.placements = placements(of: references, counts: &counts)
        return result
    }

    /// The worldspace's persistent Is Full LOD references outside `loadedCells`, in their
    /// enable state. The loaded cells draw their own.
    nonisolated func fullLODPlacements(
        worldspaceEditorID: String,
        loadedCells: Set<CellCoordinate>,
        state: WorldStateSnapshot = .empty
    ) -> DistantReferences {
        var result = DistantReferences()
        guard
            let world = try? worldChildrenGroup(
                editorID: worldspaceEditorID, localized: pluginLocalized
            )
        else { return result }
        let wanted = persistentReferences(in: world, localized: pluginLocalized).filter {
            $0.isFullLOD
                && !loadedCells.contains(CellGridManager.cellCoordinate(for: $0.placement.position))
        }
        guard !wanted.isEmpty else { return result }
        result.watch(wanted)
        var counts = BuildCounts()
        let entries = wanted.compactMap {
            runtimeEntry(formID: $0.formID, isPersistent: true, record: .reference($0))
        }
        let enabled = applyRuntimeState(
            refs: wanted, entries: entries, deltas: state.deltasByKey(),
            parentPool: persistentParentPool(in: world, localized: pluginLocalized),
            counts: &counts
        )
        result.placements = placements(of: enabled, counts: &counts)
        return result
    }

    nonisolated private func placements(
        of references: [PlacedReference], counts: inout BuildCounts
    ) -> [RenderPlacement] {
        resolveInstances(refs: references, counts: &counts)
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
