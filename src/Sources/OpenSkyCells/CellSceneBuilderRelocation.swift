// A reference `MoveTo` sent to another cell leaves its plugin cell and joins
// the target cell's build. The record comes from `PlacedRecordLookup`, because
// the cell that holds it in the plugin may not be loaded.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldInterface
import OpenSkyWorldState

nonisolated extension CellSceneBuilder.CellReferenceStateBuilder {
    /// Built from the load-order index the door transitions use.
    nonisolated public var placedRecords: PlacedRecordLookup {
        PlacedRecordLookup(
            index: owner.recordIndex.loadOrderIndexBuildingIfNeeded(),
            templates: owner.actorBuilder.resolver.actorResolversBuildingIfNeeded().template
        )
    }

    /// `refs` without the ones moved out of `cell`, plus the ones moved in. `cell` names an
    /// exterior's worldspace editor ID; nil for an interior.
    nonisolated func relocating(
        _ refs: [PlacedReference],
        into cell: (location: CellSceneLocation, worldspace: String?),
        deltas: [ReferenceKey: ReferenceStateDelta]
    ) -> [PlacedReference] {
        let movedIn = movedIn(to: cell, deltas: deltas).compactMap(\.placedReference)
        return keepingResident(refs, cell: cell, deltas: deltas, formID: \.formID) + movedIn
    }

    nonisolated func relocating(
        _ actors: [CollectedActor],
        into cell: (location: CellSceneLocation, worldspace: String?),
        deltas: [ReferenceKey: ReferenceStateDelta]
    ) -> [CollectedActor] {
        let movedIn = movedIn(to: cell, deltas: deltas).compactMap { entry in
            entry.placedActor.map { CollectedActor(actor: $0, isPersistent: entry.isPersistent) }
        }
        return keepingResident(actors, cell: cell, deltas: deltas, formID: \.actor.formID)
            + movedIn
    }

    nonisolated private func keepingResident<Item>(
        _ items: [Item],
        cell: (location: CellSceneLocation, worldspace: String?),
        deltas: [ReferenceKey: ReferenceStateDelta],
        formID: (Item) -> FormID
    ) -> [Item] {
        guard deltas.values.contains(where: { $0.component(ReferenceRelocation.self) != nil })
        else { return items }
        return items.filter { item in
            guard let key = ReferenceKey.resolve(formID(item), using: owner.formIDResolver) else {
                return true
            }
            return !(deltas[key]?.relocatesAway(from: cell.location, worldspace: cell.worldspace)
                ?? false)
        }
    }

    /// Records moved into `cell` from elsewhere, in key order.
    nonisolated private func movedIn(
        to cell: (location: CellSceneLocation, worldspace: String?),
        deltas: [ReferenceKey: ReferenceStateDelta]
    ) -> [RuntimeReferenceEntry] {
        let location = cell.location
        let keys = deltas.compactMap { key, delta in
            delta.component(ReferenceRelocation.self)?
                .lands(in: location, worldspace: cell.worldspace) == true ? key : nil
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
