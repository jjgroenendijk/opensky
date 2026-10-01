// Spawned references during a cell build: `ReferenceSpawnState` components for this cell
// become ordinary `PlacedReference` values, so the same passes move, draw, collide and
// take them. See docs/engine/reference-identity.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState
import OSLog

/// The spawned half of one build's reference set.
nonisolated public struct SpawnedReferenceBuild: Sendable {
    public let references: [PlacedReference]
    public let entries: [RuntimeReferenceEntry]

    public static let empty = SpawnedReferenceBuild(references: [], entries: [])
}

nonisolated extension CellSceneBuilder {
    /// Every spawned object `state` places in `location`, in `ReferenceKey` order. A spawn
    /// past the 24-bit object ID has no FormID, so it is dropped and counted.
    nonisolated public func spawnedReferences(
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
