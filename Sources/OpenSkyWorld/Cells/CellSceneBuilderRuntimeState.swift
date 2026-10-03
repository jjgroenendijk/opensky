// Applies runtime state during a cell build: the single point where plugin data meets
// the `WorldStateSnapshot`. Rendering and collision use the same effective placements,
// so a moved object's mesh and collider agree. Deltas come from a dictionary built once
// per build. See docs/engine/runtime-state.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState
import OSLog

/// One cell's references as a build should place them: the index entries every
/// placement keeps, the deltas that applied to them, and the effective set that
/// reaches render and collision.
nonisolated public struct EffectiveReferences: Sendable {
    /// Index entries for every reference the plugin placed, including ones
    /// runtime state hides: an object a script disabled still exists.
    public let entries: [RuntimeReferenceEntry]
    /// This build's snapshot, flattened for repeated lookup.
    public let deltas: [ReferenceKey: ReferenceStateDelta]
    /// What render and collision both place. Both read this one array, so a
    /// moved object's collision shape follows its mesh.
    public let references: [PlacedReference]
}

nonisolated extension CellSceneBuilder {
    /// Keys `entries` by the FormID a placement was authored under.
    nonisolated public func entriesByFormID(
        _ entries: [RuntimeReferenceEntry]
    ) -> [FormID: RuntimeReferenceEntry] {
        var result: [FormID: RuntimeReferenceEntry] = [:]
        result.reserveCapacity(entries.count)
        for entry in entries {
            result[entry.formID] = entry
        }
        return result
    }

    /// Indexes `refs`, adds spawned objects for `location`, and resolves them against
    /// `state`, shared by exterior and interior builds. Spawns join before
    /// `applyRuntimeState`, so a moved or hidden drop follows the same rules.
    /// `parentPool` holds references outside the cell an `XESP` link may name.
    nonisolated public func effectiveReferences(
        refs: [PlacedReference],
        collected: [CollectedReference],
        state: WorldStateSnapshot,
        location: CellSceneLocation,
        parentPool: [FormID: PlacedReference] = [:],
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
                parentPool: parentPool,
                counts: &counts
            )
        )
    }

    /// The references a build places, with runtime deltas. Disabled or deleted ones are
    /// dropped and counted; a transform override replaces DATA and XSCL. References with
    /// no entry in `entries` (unresolvable FormID) pass through.
    nonisolated public func applyRuntimeState(
        refs: [PlacedReference],
        entries: [RuntimeReferenceEntry],
        deltas: [ReferenceKey: ReferenceStateDelta],
        parentPool: [FormID: PlacedReference] = [:],
        counts: inout BuildCounts
    ) -> [PlacedReference] {
        guard !refs.isEmpty else { return refs }
        let entriesByFormID = entriesByFormID(entries)
        let enable = EnableParentResolver(deltas: deltas) { formID in
            entriesByFormID[formID] ?? parentPool[formID].flatMap { reference in
                self.runtimeEntry(formID: formID, isPersistent: true, record: .reference(reference))
            }
        }
        var effective: [PlacedReference] = []
        effective.reserveCapacity(refs.count)
        for ref in refs {
            guard let entry = entriesByFormID[ref.formID] else {
                effective.append(ref)
                continue
            }
            let resolved = ReferenceState(baseline: entry).applying(deltas[entry.key])
            if enable.hasUnresolvedParent(entry) {
                counts.unresolvedEnableParents += 1
            }
            guard !resolved.deletion.isDeleted else {
                counts.runtimeDeleted += 1
                Self.logger.info(
                    "REFR \(ref.formID.description, privacy: .public): deleted at runtime, skipped"
                )
                continue
            }
            guard enable.isEnabled(entry) else {
                if resolved.overriddenKinds.contains(.enableState) {
                    counts.runtimeDisabled += 1
                } else {
                    counts.baselineDisabled += 1
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
    nonisolated public func resolvedRuntimeState(
        for entry: RuntimeReferenceEntry,
        deltas: [ReferenceKey: ReferenceStateDelta]
    ) -> ReferenceState {
        ReferenceState(baseline: entry).applying(deltas[entry.key])
    }
}
