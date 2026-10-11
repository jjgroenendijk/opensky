// Sit packages: pick a free furniture seat the actor may use, seat the actor
// there, and tell the furniture's scripts. See docs/engine/package-schedules.md,
// "Furniture".

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// One marker of one furniture reference.
struct SeatKey: Hashable {
    let furniture: ReferenceKey
    let index: Int
}

extension AIWorldAdapter {
    func packageSeat(
        from target: Package.Target, actor: ReferenceKey, aliasQuest: FormID?
    ) -> PackageSeat? {
        guard
            let furniture = packageTargetKey(target, aliasQuest: aliasQuest),
            let streamer = game.streamer,
            let formID = streamer.referenceEntry(key: furniture)?.formID,
            let seats = streamer.residentInteraction(reference: formID)?.seats
        else { return nil }
        let free = seats.indices.filter { index in
            let holder = seatHolders[SeatKey(furniture: furniture, index: index)]
            return holder == nil || holder == actor
        }
        // A seat with a keyword is kept for actors whose base has it, and wins for them.
        let keyed = free.first { index in
            seats[index].keyword.map { actorHasKeyword(actor, $0) == true } ?? false
        }
        guard let index = keyed ?? free.first(where: { seats[$0].keyword == nil }) else {
            return nil
        }
        seatHolders[SeatKey(furniture: furniture, index: index)] = actor
        return PackageSeat(furniture: furniture, index: index, seat: seats[index])
    }

    func seatPackageActor(_ actor: ReferenceKey, in seat: PackageSeat) {
        game.streamer?.restActor(actor, at: ReferenceTransformOverride(
            position: seat.seat.position, rotation: SIMD3(0, 0, seat.seat.heading)
        ))
        game.scripts.bridge?.activate(seat.furniture, by: actor, togglesOpen: false)
    }

    func unseatPackageActor(_ actor: ReferenceKey, from seat: PackageSeat) {
        let key = SeatKey(furniture: seat.furniture, index: seat.index)
        if seatHolders[key] == actor {
            seatHolders[key] = nil
        }
    }

    /// `KWDA` of the actor's base, as the Papyrus `HasKeyword` reads it.
    private func actorHasKeyword(_ actor: ReferenceKey, _ keyword: FormID) -> Bool? {
        guard
            let bridge = game.scripts.bridge,
            let keywordKey = bridge.referenceKey(forFormID: keyword)
        else { return nil }
        return bridge.formHasKeyword(actor, keyword: keywordKey)
    }
}
