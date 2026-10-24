// Who holds each furniture seat, so two actors never share one. A seat with a FURN
// `FNMK` keyword is kept for actors that have it, and a seat the record's `MNAM`
// turns off is no one's (docs/engine/furniture.md).

import OpenSkyFormatsESM
import OpenSkyWorldInterface
import simd

nonisolated public struct FurnitureSeatLedger: Sendable {
    private struct SeatKey: Hashable, Sendable {
        let furniture: ReferenceKey
        let index: Int
    }

    private var holders: [SeatKey: ReferenceKey] = [:]

    public init() {}

    /// Reserves a free seat for `actor`. A keyed seat wins for an actor with its keyword,
    /// then a seat of `animation` over one of another type, then the seat nearest `near`.
    /// The furniture's rules may keep the actor out, as a perch keeps out all but dragons.
    public mutating func reserve(
        in furniture: ReferenceKey,
        seats: [FurnitureSeat],
        actor: ReferenceKey,
        animation: UInt16? = nil,
        near: SIMD3<Float>? = nil,
        traits: FurnitureActorTraits = FurnitureActorTraits(),
        hasKeyword: (FormID) -> Bool
    ) -> PackageSeat? {
        let free = seats.indices.filter { index in
            let holder = holders[SeatKey(furniture: furniture, index: index)]
            return seats[index].isEnabled && (holder == nil || holder == actor)
        }.sorted { first, second in
            guard let near else { return first < second }
            return simd_distance(seats[first].position, near)
                < simd_distance(seats[second].position, near)
        }
        let allowed = free.filter {
            seats[$0].rules.admits(traits) && seats[$0].keyword.map(hasKeyword) ?? true
        }
        let keyed = allowed.filter { seats[$0].keyword != nil }
        let open = allowed.filter { seats[$0].keyword == nil }
        let ordered = keyed.filter { seats[$0].animationType == animation }
            + keyed + open.filter { seats[$0].animationType == animation } + open
        guard let index = animation == nil ? (keyed + open).first : ordered.first else {
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

    /// Gives the seat to `actor`, whoever held it.
    public mutating func hold(_ seat: PackageSeat, by actor: ReferenceKey) {
        holders[SeatKey(furniture: seat.furniture, index: seat.index)] = actor
    }

    /// Frees every seat `actor` holds, in every piece of furniture.
    public mutating func releaseAll(heldBy actor: ReferenceKey) {
        holders = holders.filter { $0.value != actor }
    }

    public func holder(of furniture: ReferenceKey, index: Int) -> ReferenceKey? {
        holders[SeatKey(furniture: furniture, index: index)]
    }

    /// Every held seat of the furniture, by marker index.
    public func holders(of furniture: ReferenceKey) -> [Int: ReferenceKey] {
        var result: [Int: ReferenceKey] = [:]
        for (key, actor) in holders where key.furniture == furniture {
            result[key.index] = actor
        }
        return result
    }
}
