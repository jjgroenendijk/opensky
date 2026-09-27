// Spawned references during a cell build (issue #177, roadmap item 12.1.3),
// split from CellSceneBuilderRuntimeState.swift for file-length limits.
//
// A spawned object is not in the plugin, so nothing collects it: this file
// reads `ReferenceSpawnState` components out of the build's snapshot and turns
// the ones that name this cell into ordinary `PlacedReference` values with
// ordinary `RuntimeReferenceEntry` index entries. From that point on they are
// indistinguishable from authored placements — the same `applyRuntimeState`
// pass moves or hides them, the same instance resolution draws them, the same
// collision build makes them solid and the same interaction resolution makes
// them takeable. That is the whole reason drop reuses the component system
// rather than adding a parallel list of runtime objects.
//
// Documented in docs/engine/runtime-state.md.

import Foundation
import OSLog

/// The spawned half of one build's reference set.
nonisolated struct SpawnedReferenceBuild {
    let references: [PlacedReference]
    let entries: [RuntimeReferenceEntry]

    static let empty = SpawnedReferenceBuild(references: [], entries: [])
}

nonisolated extension CellSceneBuilder {
    /// Every spawned object `state` places in `location`.
    ///
    /// Snapshot entries are already in `ReferenceKey` total order, so the
    /// result is deterministic without sorting: two builds of the same cell
    /// against the same state place the same objects in the same order.
    ///
    /// A spawn whose generated sequence has outrun the 24-bit object ID has no
    /// FormID to be addressed by, so it is dropped and counted rather than
    /// aliased onto another object's ID.
    nonisolated func spawnedReferences(
        in location: CellSceneLocation,
        state: WorldStateSnapshot,
        counts: inout BuildCounts
    ) -> SpawnedReferenceBuild {
        guard !state.entries.isEmpty else { return .empty }
        var references: [PlacedReference] = []
        var entries: [RuntimeReferenceEntry] = []
        for entry in state.entries {
            guard
                let spawn = entry.delta.component(ReferenceSpawnState.self),
                spawn.location == location
            else { continue }
            guard let formID = SpawnedReferenceIdentity.formID(for: entry.key) else {
                counts.unaddressableSpawns += 1
                Self.logger.warning(
                    """
                    [WARNING] spawned reference \(entry.key.description, privacy: .public): \
                    no FormID available, skipped
                    """
                )
                continue
            }
            let reference = PlacedReference(spawn: spawn, formID: formID)
            references.append(reference)
            entries.append(RuntimeReferenceEntry(
                key: entry.key,
                formID: formID,
                // Spawned objects outlive the streaming lifetime of the cell
                // they are in: the store holds them, not the scene, so a
                // dropped item is still there on the way back.
                isPersistent: true,
                record: .reference(reference)
            ))
        }
        counts.spawnedRefs = references.count
        return SpawnedReferenceBuild(references: references, entries: entries)
    }
}
