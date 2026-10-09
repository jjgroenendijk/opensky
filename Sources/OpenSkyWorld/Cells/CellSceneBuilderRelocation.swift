// A reference `MoveTo` sent to another cell leaves its plugin cell and joins
// the target cell's build. The record comes from `PlacedRecordLookup`, because
// the cell that holds it in the plugin may not be loaded.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

nonisolated extension CellSceneBuilder {
    /// Built from the load-order index the door transitions use.
    nonisolated public var placedRecords: PlacedRecordLookup {
        PlacedRecordLookup(
            index: loadOrderIndexBuildingIfNeeded(),
            templates: actorResolversBuildingIfNeeded().template
        )
    }

    /// `refs` without the ones moved out of `location`, plus the ones moved in.
    nonisolated func relocating(
        _ refs: [PlacedReference],
        into location: CellSceneLocation,
        deltas: [ReferenceKey: ReferenceStateDelta]
    ) -> [PlacedReference] {
        let movedIn = movedIn(to: location, deltas: deltas).compactMap(\.placedReference)
        return keepingResident(refs, location: location, deltas: deltas, formID: \.formID)
            + movedIn
    }

    nonisolated func relocating(
        _ actors: [CollectedActor],
        into location: CellSceneLocation,
        deltas: [ReferenceKey: ReferenceStateDelta]
    ) -> [CollectedActor] {
        let movedIn = movedIn(to: location, deltas: deltas).compactMap { entry in
            entry.placedActor.map { CollectedActor(actor: $0, isPersistent: entry.isPersistent) }
        }
        return keepingResident(actors, location: location, deltas: deltas, formID: \.actor.formID)
            + movedIn
    }

    nonisolated private func keepingResident<Item>(
        _ items: [Item],
        location: CellSceneLocation,
        deltas: [ReferenceKey: ReferenceStateDelta],
        formID: (Item) -> FormID
    ) -> [Item] {
        guard deltas.values.contains(where: { $0.component(ReferenceRelocation.self) != nil })
        else { return items }
        return items.filter { item in
            guard let key = ReferenceKey.resolve(formID(item), using: formIDResolver) else {
                return true
            }
            return !(deltas[key]?.relocatesAway(from: location) ?? false)
        }
    }

    /// Records moved into `location` from elsewhere, in key order.
    nonisolated private func movedIn(
        to location: CellSceneLocation,
        deltas: [ReferenceKey: ReferenceStateDelta]
    ) -> [RuntimeReferenceEntry] {
        let keys = deltas.compactMap { key, delta in
            delta.component(ReferenceRelocation.self)?.location == location ? key : nil
        }
        guard !keys.isEmpty else { return [] }
        let lookup = placedRecords
        return keys.sorted().compactMap { key in
            guard let entry = lookup.entry(for: key), lookup.home(of: entry) != location
            else { return nil }
            return entry
        }
    }
}
