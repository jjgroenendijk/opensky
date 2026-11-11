// Large references and Is Full LOD references past the loaded grid: the distant LOD ring
// draws them with their full model, in their enable state (docs/engine/distant-lod.md).

import OpenSkyFormatsCore
import OpenSkyFormatsESM
public import OpenSkyRendering
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

nonisolated extension CellReferenceBuilder {
    /// The ring's large references, placed as their cells place them, in the enable state
    /// `state` and their enable parents give, as in their own cells.
    nonisolated func largeReferencePlacements(
        worldspaceEditorID: String,
        cells: Set<CellCoordinate>,
        state: WorldStateSnapshot = .empty
    ) -> DistantReferences {
        let listed = largeReferences(worldspaceEditorID: worldspaceEditorID, cells: cells)
        return cellReferencePlacements(
            worldspaceEditorID: worldspaceEditorID, cells: Set(listed.keys), state: state
        ) { cell, _ in listed[cell] ?? [] }
    }

    /// The references `pick` names in each of `cells`, read from their cell and put in the
    /// enable state their own cell would give them.
    nonisolated private func cellReferencePlacements(
        worldspaceEditorID: String,
        cells: Set<CellCoordinate>,
        state: WorldStateSnapshot,
        pick: (CellCoordinate, [CollectedReference]) -> Set<UInt32>
    ) -> DistantReferences {
        var counts = BuildCounts()
        var references: [PlacedReference] = []
        var result = DistantReferences()
        let deltas = state.deltasByKey()
        for cell in cells.sorted(by: { ($0.x, $0.y) < ($1.x, $1.y) }) {
            guard
                let source = attempt({
                    try owner.recordIndex.exteriorBuildSource(
                        worldspaceEditorID: worldspaceEditorID, gridX: cell.x, gridY: cell.y
                    )
                })
            else { continue }
            let collected = collectTaggedReferences(in: source.cell, counts: &counts)
            let wanted = pick(cell, collected)
            guard !wanted.isEmpty else { continue }
            let placed = owner.interiorBuilder.exteriorReferences(
                local: collected.map(\.reference), world: source.world,
                coordinate: cell, localized: owner.pluginLocalized
            ).filter { wanted.contains($0.formID.rawValue) }
            result.watch(placed)
            references += applyRuntimeState(
                refs: placed,
                entries: referenceEntries(refs: placed, collected: collected),
                deltas: deltas,
                parentPool: owner.interiorBuilder.persistentParentPool(
                    in: source.world,
                    localized: owner.pluginLocalized
                ),
                counts: &counts
            )
        }
        result.placements = placements(of: references, counts: &counts)
        return result
    }

    /// The temporary Is Full LOD references in the worldspace's cells outside `loadedCells`.
    /// The first walk finds the cells that hold one; later builds read only those cells.
    nonisolated func temporaryFullLODPlacements(
        worldspaceEditorID: String,
        loadedCells: Set<CellCoordinate>,
        state: WorldStateSnapshot = .empty
    ) -> DistantReferences {
        guard
            let world = attempt({
                try owner.worldChildrenGroup(
                    editorID: worldspaceEditorID, localized: owner.pluginLocalized
                )
            })
        else { return DistantReferences() }
        let cells = temporaryFullLODCells(in: world).subtracting(loadedCells)
        return cellReferencePlacements(
            worldspaceEditorID: worldspaceEditorID, cells: cells, state: state
        ) { _, collected in
            Set(collected.lazy.filter { !$0.isPersistent && $0.reference.isFullLOD }
                .map(\.reference.formID.rawValue))
        }
    }

    /// The cells whose temporary children hold a live REFR with the Is Full LOD flag. Only
    /// the record header is read, so the walk decodes no reference.
    nonisolated func temporaryFullLODCells(in world: FoundWorld) -> Set<CellCoordinate> {
        let key = world.formID.rawValue
        if let cached = owner.temporaryFullLODCellIndex[key] {
            return cached
        }
        var found: Set<CellCoordinate> = []
        for (grid, cell) in owner.recordIndex.exteriorCells(
            in: world,
            localized: owner.pluginLocalized
        ) {
            guard let cellChildren = cell.children, let groups = owner.childrenOrSkip(cellChildren)
            else { continue }
            for case let .group(group) in groups where group.kind == .cellTemporaryChildren {
                let records = owner.childrenOrSkip(group) ?? []
                let holds = records.contains { child in
                    guard case let .record(record) = child else { return false }
                    return record.type == "REFR" && !record.isDeleted
                        && record.flags.rawValue & PlacedReference.fullLODFlag != 0
                }
                if holds {
                    found.insert(CellCoordinate(x: grid.x, y: grid.y))
                }
            }
        }
        owner.temporaryFullLODCellIndex[key] = found
        return found
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
            let world = attempt({
                try owner.worldChildrenGroup(
                    editorID: worldspaceEditorID, localized: owner.pluginLocalized
                )
            })
        else { return result }
        let wanted = owner.interiorBuilder.persistentReferences(
            in: world,
            localized: owner.pluginLocalized
        ).filter {
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
            parentPool: owner.interiorBuilder.persistentParentPool(
                in: world,
                localized: owner.pluginLocalized
            ),
            counts: &counts
        )
        result.placements = placements(of: enabled, counts: &counts)
        return result
    }

    nonisolated private func placements(
        of references: [PlacedReference], counts: inout BuildCounts
    ) -> [RenderPlacement] {
        owner.resolveInstances(refs: references, counts: &counts)
            .filter { !$0.model.meshes.isEmpty }
            .map { instance in
                RenderPlacement(
                    model: instance.model,
                    transform: instance.transform,
                    bounds: owner.meshes.bounds(
                        forPath: instance.modelPath,
                        surface: instance.surface
                    )?
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
            let world = owner.waterBuilder.worldspaceIndexBuildingIfNeeded().values
                .first(where: { $0.editorID == worldspaceEditorID })
        else { return [:] }
        return largeReferenceIndex(world: world.formID.rawValue).filter { cells.contains($0.key) }
    }

    /// Each plugin's `WRLD` lists only the large references it adds, so the lists of
    /// every plugin are joined, as `RNAM` counts on the install show.
    nonisolated private func largeReferenceIndex(world: UInt32) -> [CellCoordinate: Set<UInt32>] {
        if let cached = owner.largeReferenceIndex[world] {
            return cached
        }
        var skipped = SkippedRecords()
        let versions = owner.interiorBuilder.loadOrderIndexBuildingIfNeeded().loadOrder
            .decodeEveryVersion(
                of: "WRLD",
                skipped: &skipped,
                using: WorldspaceLargeReferenceCell.decodeAll(record:)
            )
        var index: [CellCoordinate: Set<UInt32>] = [:]
        for entry in (versions[world] ?? []).joined() {
            for reference in entry.references {
                let cell = CellCoordinate(x: Int32(reference.cell.x), y: Int32(reference.cell.y))
                index[cell, default: []].insert(reference.reference.rawValue)
            }
        }
        owner.largeReferenceIndex[world] = index
        return index
    }
}
