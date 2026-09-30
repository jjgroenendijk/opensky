// Reference collection and runtime-index assembly. Persistent and temporary
// placements render alike, so collection flattens them, but the runtime index
// needs to know which group each came from (UESP "Mod File Format" — Groups).

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyWorldState
import OSLog

/// A decoded REFR plus the children group it was stored in.
nonisolated public struct CollectedReference: Sendable {
    public let reference: PlacedReference
    public let isPersistent: Bool
}

/// A decoded ACHR plus the children group it was stored in.
nonisolated public struct CollectedActor: Sendable {
    public let actor: PlacedActor
    public let isPersistent: Bool
}

nonisolated extension CellSceneBuilder {
    /// Live REFRs from the persistent and temporary children groups, tagged
    /// with their group. Other record types are not static placements and are
    /// not counted (docs/engine/cell-scene.md). A REFR that fails to decode is
    /// counted as malformed.
    nonisolated public func collectTaggedReferences(
        in cellChildren: ESMGroup?,
        counts: inout BuildCounts
    ) -> [CollectedReference] {
        guard let cellChildren, let children = childrenOrSkip(cellChildren) else { return [] }
        var refs: [CollectedReference] = []
        for case let .group(group) in children {
            guard
                group.kind == .cellPersistentChildren || group.kind == .cellTemporaryChildren,
                let records = childrenOrSkip(group)
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
    nonisolated public func collectReferences(
        in cellChildren: ESMGroup?,
        counts: inout BuildCounts
    ) -> [PlacedReference] {
        collectTaggedReferences(in: cellChildren, counts: &counts).map(\.reference)
    }

    /// Index entries for the references a finished cell placed. A reference from
    /// a local temporary group is temporary; everything else, including refs
    /// merged from the worldspace persistent CELL, is persistent.
    nonisolated public func referenceEntries(
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

    nonisolated public func actorEntries(_ collected: [CollectedActor]) -> [RuntimeReferenceEntry] {
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
    nonisolated public func runtimeEntry(
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
