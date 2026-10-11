// The references a location lists by location ref type (`LCRT`), which a quest alias
// of the "location alias reference" kind fills from. See docs/formats/locations.md.

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

    /// The references of `type` in `locationID`, then in its child locations, nearest
    /// generation first and FormID order within one. A child is any location whose
    /// PNAM chain reaches `locationID`.
    public func specialReferencesWithChildren(
        ofType type: ReferenceKey, in locationID: ResolvedFormID
    ) -> [ReferenceKey] {
        let children = locations.keys
            .filter { $0 != locationID && isWithin($0, ancestor: locationID) }
            .map { (id: $0, depth: parentChain(of: $0).count) }
            .sorted { lhs, rhs in
                (lhs.depth, lhs.id.plugin, lhs.id.objectID)
                    < (rhs.depth, rhs.id.plugin, rhs.id.objectID)
            }
        return ([locationID] + children.map(\.id)).flatMap {
            specialReferences(ofType: type, in: $0)
        }
    }
}
