import Foundation
public import OpenSkyGameData

nonisolated extension RuntimeReferenceIndex {
    /// An index of the load order's persistent placements, loaded or not.
    public init(persistent placements: [PersistentPlacement]) {
        self.init(entries: placements.map { placement in
            let record: RuntimeReferenceRecord = switch placement.record {
            case let .reference(reference): .reference(reference)
            case let .actor(actor): .actor(actor)
            }
            return RuntimeReferenceEntry(
                key: placement.key, formID: placement.formID, isPersistent: true, record: record
            )
        })
    }
}
