// The `HAZD` record as the hazard runtime reads it. See docs/formats/hazards.md.

import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated extension HazardStore {
    /// The runtime numbers for `key`, or nil when the record is missing or has no `DATA`.
    public func spec(for key: ReferenceKey) -> HazardSpec? {
        guard
            case let .plugin(name, objectID) = key,
            let record = hazards.record(ResolvedFormID(plugin: name, objectID: objectID)),
            let properties = record.record.properties
        else { return nil }
        return HazardSpec(
            hazard: key,
            name: record.record.editorID ?? key.description,
            spell: links(of: record).spell.map { ReferenceKey(resolved: $0.target) },
            radius: properties.radius,
            lifetime: properties.lifetime,
            targetInterval: properties.targetInterval,
            limit: properties.limit,
            affectsPlayerOnly: properties.affectsPlayerOnly
        )
    }
}
