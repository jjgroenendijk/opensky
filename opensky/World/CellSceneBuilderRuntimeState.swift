// Runtime-state application during a cell build (issue #160, roadmap item
// 10.1.3), split from CellSceneBuilder.swift for file-length limits.
//
// The builder decodes what the plugin authored; the `WorldStateStore` above it
// holds every deviation the running game has recorded since. This file is the
// single point where the two meet: a build takes a `WorldStateSnapshot`,
// resolves each keyed reference against it, and hands the *effective* set of
// placements onward. Render instancing and collision both consume that same
// set, which is what keeps a moved object's mesh and its collision shape in
// the same place.
//
// Deltas are looked up through a dictionary materialized once per build rather
// than through `WorldStateSnapshot.subscript(key:)`, which is a linear scan.
//
// Documented in docs/engine/runtime-state.md.

import Foundation
import OSLog

/// One cell's references as a build should place them: the index entries every
/// placement keeps, the deltas that applied to them, and the effective set that
/// reaches render and collision.
nonisolated struct EffectiveReferences {
    /// Index entries for every reference the plugin placed, including ones
    /// runtime state hides: an object a script disabled still exists.
    let entries: [RuntimeReferenceEntry]
    /// This build's snapshot, flattened for repeated lookup.
    let deltas: [ReferenceKey: ReferenceStateDelta]
    /// What render and collision both place. Both read this one array, so a
    /// moved object's collision shape follows its mesh.
    let references: [PlacedReference]
}

extension CellSceneBuilder {
    /// Keys `entries` by the FormID a placement was authored under.
    nonisolated func entriesByFormID(
        _ entries: [RuntimeReferenceEntry]
    ) -> [FormID: RuntimeReferenceEntry] {
        var result: [FormID: RuntimeReferenceEntry] = [:]
        result.reserveCapacity(entries.count)
        for entry in entries {
            result[entry.formID] = entry
        }
        return result
    }

    /// Indexes `refs`, adds whatever the running game spawned into `location`,
    /// resolves the union against `state`, and returns both halves. Exterior
    /// and interior builds share this so runtime state applies at exactly one
    /// point in either path.
    ///
    /// Spawned objects join *before* `applyRuntimeState` rather than being
    /// appended to its output, so a dropped item that was later moved, disabled
    /// or picked back up goes through the same resolution an authored
    /// placement does instead of needing a second set of rules (issue #177).
    nonisolated func effectiveReferences(
        refs: [PlacedReference],
        collected: [CollectedReference],
        state: WorldStateSnapshot,
        location: CellSceneLocation,
        counts: inout BuildCounts
    ) -> EffectiveReferences {
        let spawned = spawnedReferences(in: location, state: state, counts: &counts)
        let entries = referenceEntries(refs: refs, collected: collected) + spawned.entries
        let deltas = state.deltasByKey()
        return EffectiveReferences(
            entries: entries,
            deltas: deltas,
            references: applyRuntimeState(
                refs: refs + spawned.references,
                entries: entries,
                deltas: deltas,
                counts: &counts
            )
        )
    }

    /// The references a build should actually place, with runtime deltas
    /// applied.
    ///
    /// A reference whose resolved state is not visible — disabled or deleted at
    /// runtime — is dropped and counted, exactly as an initially-disabled
    /// record is. A reference carrying a transform override is placed at the
    /// override's position, rotation and scale instead of the record's DATA and
    /// XSCL values.
    ///
    /// - Parameters:
    ///   - refs: the post-merge reference set for this cell.
    ///   - entries: the runtime index entries for `refs`, which carry the
    ///     `ReferenceKey` a delta is addressed by. References with no entry
    ///     (an unresolvable FormID) have no runtime identity and pass through
    ///     untouched.
    ///   - deltas: this build's snapshot, flattened by `deltasByKey()`.
    nonisolated func applyRuntimeState(
        refs: [PlacedReference],
        entries: [RuntimeReferenceEntry],
        deltas: [ReferenceKey: ReferenceStateDelta],
        counts: inout BuildCounts
    ) -> [PlacedReference] {
        guard !deltas.isEmpty, !refs.isEmpty else { return refs }
        let entriesByFormID = entriesByFormID(entries)
        var effective: [PlacedReference] = []
        effective.reserveCapacity(refs.count)
        for ref in refs {
            guard
                let entry = entriesByFormID[ref.formID],
                let delta = deltas[entry.key]
            else {
                effective.append(ref)
                continue
            }
            let resolved = ReferenceState(baseline: entry).applying(delta)
            let id = ref.formID.description
            guard resolved.isVisible else {
                if resolved.deletion.isDeleted {
                    counts.runtimeDeleted += 1
                    Self.logger.info(
                        "REFR \(id, privacy: .public): deleted at runtime, skipped"
                    )
                } else {
                    counts.runtimeDisabled += 1
                    Self.logger.info(
                        "REFR \(id, privacy: .public): disabled at runtime, skipped"
                    )
                }
                continue
            }
            guard resolved.overriddenKinds.contains(.transform) else {
                effective.append(ref)
                continue
            }
            var moved = ref
            moved.placement = resolved.transform.placement
            moved.scale = resolved.transform.scale
            effective.append(moved)
        }
        return effective
    }

    /// `entry`'s plugin baseline with this build's delta laid over it. The
    /// baseline is re-derived from the decoded record, never cached, so it
    /// cannot go stale against a reloaded plugin.
    nonisolated func resolvedRuntimeState(
        for entry: RuntimeReferenceEntry,
        deltas: [ReferenceKey: ReferenceStateDelta]
    ) -> ReferenceState {
        ReferenceState(baseline: entry).applying(deltas[entry.key])
    }
}
