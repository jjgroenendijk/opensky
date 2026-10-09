// The references a location lists by location ref type (`LCRT`), which a quest alias
// of the "location alias reference" kind fills from. See docs/formats/locations.md.

import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated extension LocationStore {
    /// The references `locationID` lists under `type`, in file order: `LCSR`, then
    /// `ACSR`, without the ones `RCSR` removes.
    public func specialReferences(
        ofType type: ReferenceKey, in locationID: ResolvedFormID
    ) -> [ReferenceKey] {
        guard let resolved = location(locationID) else { return [] }
        let key = { (raw: FormID) in
            resolvedID(raw, fromPlugin: resolved.sourcePlugin).map(ReferenceKey.init(resolved:))
        }
        let place = resolved.location
        let removed = Set(place.removedSpecialReferences.compactMap(key))
        return (place.specialReferences + place.addedSpecialReferences)
            .filter { key($0.type) == type }
            .compactMap { key($0.reference) }
            .filter { !removed.contains($0) }
    }
}
