// Who holds each furniture seat, so two package actors never share one. A seat
// with a FURN `FNMK` keyword is kept for actors that have it
// (docs/engine/package-schedules.md, "Furniture").

import OpenSkyFormatsESM
import OpenSkyWorldInterface

nonisolated public struct PackageSeatLedger: Sendable {
    private struct SeatKey: Hashable, Sendable {
        let furniture: ReferenceKey
        let index: Int
    }

    private var holders: [SeatKey: ReferenceKey] = [:]

    public init() {}

    /// Reserves a free seat for `actor`. A keyed seat wins for an actor with its keyword.
    public mutating func reserve(
        in furniture: ReferenceKey,
        seats: [FurnitureSeat],
        actor: ReferenceKey,
        hasKeyword: (FormID) -> Bool
    ) -> PackageSeat? {
        let free = seats.indices.filter { index in
            let holder = holders[SeatKey(furniture: furniture, index: index)]
            return holder == nil || holder == actor
        }
        let keyed = free.first { seats[$0].keyword.map(hasKeyword) ?? false }
        guard let index = keyed ?? free.first(where: { seats[$0].keyword == nil }) else {
            return nil
        }
        holders[SeatKey(furniture: furniture, index: index)] = actor
        return PackageSeat(furniture: furniture, index: index, seat: seats[index])
    }

    /// Frees the seat, but only while `actor` still holds it.
    public mutating func release(_ seat: PackageSeat, by actor: ReferenceKey) {
        let key = SeatKey(furniture: seat.furniture, index: seat.index)
        if holders[key] == actor {
            holders[key] = nil
        }
    }

    public func holder(of furniture: ReferenceKey, index: Int) -> ReferenceKey? {
        holders[SeatKey(furniture: furniture, index: index)]
    }
}
