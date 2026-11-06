// A boss's death clears a location when every reference it lists as a boss is dead or
// disabled. See docs/formats/locations.md#cleared-locations.

import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated extension LocationStore {
    /// The locations `victim` was a boss of whose other bosses are all done: dead or
    /// disabled. A location without bosses never clears this way.
    public func locationsCleared(
        byDeathOf victim: ReferenceKey, isDone: (ReferenceKey) -> Bool
    ) -> [ResolvedFormID] {
        guard let bossType else { return [] }
        return (bossLocations[victim.namingPlayer] ?? []).filter { location in
            let bosses = specialReferences(ofType: bossType, in: location)
            return !bosses.isEmpty && bosses.allSatisfy { $0 == victim || isDone($0) }
        }
    }

    /// Whether clearing `location` plays the dungeon-cleared music.
    public func playsClearedMusic(_ location: ResolvedFormID) -> Bool {
        clearableKeyword.map { hasKeyword($0, in: location) } ?? false
    }

    static func locations(
        listing type: ReferenceKey?,
        in locations: some Sequence<ResolvedLocation>,
        index: RecordIndex
    ) -> [ReferenceKey: [ResolvedFormID]] {
        guard let type else { return [:] }
        var result: [ReferenceKey: [ResolvedFormID]] = [:]
        for resolved in locations {
            let key = { (raw: FormID) in
                index.resolvedID(raw, fromPlugin: resolved.sourcePlugin)
                    .map(ReferenceKey.init(resolved:))
            }
            let place = resolved.location
            let removed = Set(place.removedSpecialReferences.compactMap(key))
            for special in place.specialReferences + place.addedSpecialReferences
                where key(special.type) == type
            {
                guard let reference = key(special.reference), !removed.contains(reference)
                else { continue }
                result[reference.namingPlayer, default: []].append(resolved.id)
            }
        }
        return result
    }
}
