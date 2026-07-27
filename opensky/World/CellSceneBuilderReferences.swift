// Reference collection and runtime-index assembly, split from
// CellSceneBuilder.swift for file-length limits.
//
// A cell stores placements in two children groups: persistent records survive
// beyond the cell's streaming lifetime, temporary records do not. The render
// path treats both alike, so collection flattens them; the runtime index needs
// the distinction, so collection also tags each record with the group it came
// from. Group nesting reference: UESP "Skyrim Mod:Mod File Format" — Groups.

import Foundation
import OSLog

/// A decoded REFR plus the children group it was stored in.
nonisolated struct CollectedReference {
    let reference: PlacedReference
    let isPersistent: Bool
}

/// A decoded ACHR plus the children group it was stored in.
nonisolated struct CollectedActor {
    let actor: PlacedActor
    let isPersistent: Bool
}

extension CellSceneBuilder {
    /// REFR records from the cell's persistent + temporary children groups,
    /// each tagged with its group. LAND is handled separately (buildTerrain);
    /// other non-REFR types (NAVM, ACHR, PGRE, ...) are not static placements
    /// — ignored deliberately and not counted (skip taxonomy,
    /// docs/engine/cell-scene.md). Deleted REFRs place nothing -> also
    /// ignored. A REFR that fails to decode is malformed.
    nonisolated func collectTaggedReferences(
        in cellChildren: ESMGroup?,
        counts: inout BuildCounts
    ) -> [CollectedReference] {
        guard let cellChildren, let children = try? cellChildren.children() else {
            if cellChildren != nil {
                Self.logger.warning("malformed cell-children group skipped")
            }
            return []
        }
        var refs: [CollectedReference] = []
        for case let .group(group) in children {
            guard
                group.kind == .cellPersistentChildren || group.kind == .cellTemporaryChildren,
                let records = try? group.children()
            else { continue }
            let isPersistent = group.kind == .cellPersistentChildren
            for case let .record(record) in records where record.type == "REFR" {
                guard !record.isDeleted else { continue }
                counts.totalRefs += 1
                do {
                    try refs.append(CollectedReference(
                        reference: PlacedReference(record: record), isPersistent: isPersistent
                    ))
                } catch {
                    counts.malformedRefs += 1
                    let id = FormID(record.formID).description
                    Self.logger.warning("malformed REFR \(id, privacy: .public) skipped")
                }
            }
        }
        return refs
    }

    /// Untagged collection for the render and collision paths, which place
    /// persistent and temporary records identically.
    nonisolated func collectReferences(
        in cellChildren: ESMGroup?,
        counts: inout BuildCounts
    ) -> [PlacedReference] {
        collectTaggedReferences(in: cellChildren, counts: &counts).map(\.reference)
    }

    /// Index entries for the references a finished cell actually placed.
    ///
    /// `refs` is the post-merge, post-dedupe set the scene was built from;
    /// `collected` is this cell's own children groups. A reference decoded
    /// from a local temporary group is temporary, and everything else in the
    /// final set is persistent — refs merged in from the worldspace persistent
    /// CELL are stored there precisely because they are persistent.
    nonisolated func referenceEntries(
        refs: [PlacedReference],
        collected: [CollectedReference]
    ) -> [RuntimeReferenceEntry] {
        let temporaryIDs = Set(
            collected.lazy.filter { !$0.isPersistent }.map(\.reference.formID)
        )
        return refs.compactMap { ref in
            runtimeEntry(
                formID: ref.formID,
                isPersistent: !temporaryIDs.contains(ref.formID),
                record: .reference(ref)
            )
        }
    }

    nonisolated func actorEntries(_ collected: [CollectedActor]) -> [RuntimeReferenceEntry] {
        collected.compactMap { entry in
            runtimeEntry(
                formID: entry.actor.formID,
                isPersistent: entry.isPersistent,
                record: .actor(entry.actor)
            )
        }
    }

    /// Nil when the FormID is null or otherwise unresolvable against the
    /// plugin's master list: an unkeyed record has no runtime identity, so it
    /// is left out of the index rather than given a placeholder key.
    nonisolated func runtimeEntry(
        formID: FormID,
        isPersistent: Bool,
        record: RuntimeReferenceRecord
    ) -> RuntimeReferenceEntry? {
        guard let key = ReferenceKey.resolve(formID, using: formIDResolver) else {
            return nil
        }
        return RuntimeReferenceEntry(
            key: key, formID: formID, isPersistent: isPersistent, record: record
        )
    }
}
