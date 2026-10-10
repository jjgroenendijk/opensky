// The persistent placements an `XESP` link may name. A parent is persistent, and it
// can be an object or an actor (CK wiki, "Enable Parent"). See docs/engine/traps.md.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyWorldState

nonisolated public struct EnableParentPool: Sendable {
    public var references: [FormID: PlacedReference]
    public var actors: [FormID: PlacedActor]

    public init(
        references: [FormID: PlacedReference] = [:],
        actors: [FormID: PlacedActor] = [:]
    ) {
        self.references = references
        self.actors = actors
    }
}

nonisolated extension CellSceneBuilder {
    /// Finds a parent in the build's own `entries` first, then in `pool`.
    nonisolated public func enableResolver(
        entries: [FormID: RuntimeReferenceEntry],
        pool: EnableParentPool,
        deltas: [ReferenceKey: ReferenceStateDelta]
    ) -> EnableParentResolver {
        EnableParentResolver(deltas: deltas) { formID in
            if let entry = entries[formID] {
                return entry
            }
            if let reference = pool.references[formID] {
                return self.runtimeEntry(
                    formID: formID, isPersistent: true, record: .reference(reference)
                )
            }
            return pool.actors[formID].flatMap {
                self.runtimeEntry(formID: formID, isPersistent: true, record: .actor($0))
            }
        }
    }
}
