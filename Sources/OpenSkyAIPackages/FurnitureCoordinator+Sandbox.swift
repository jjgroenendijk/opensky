// The seat a sandboxing actor takes: free, inside the sandbox's area, of a kind its
// package allows, owned by no one else, and not the furniture it just left.
// Creation Kit wiki "Sandbox (Procedure)"; docs/engine/sandbox.md.

import OpenSkyFormatsESM
import OpenSkyWorldInterface
import simd

extension FurnitureCoordinator {
    /// Reserves the nearest seat the sandbox may use. The wiki scores the object the
    /// sandbox just used as zero, so that furniture is skipped.
    public func sandboxSeat(
        for actor: ReferenceKey, in request: SandboxSeatRequest
    ) -> PackageSeat? {
        guard isEnabled, let world else { return nil }
        let near = world.furnitureActorPosition(actor) ?? request.center
        let candidates = world.residentFurniture().compactMap { furniture -> SandboxCandidate? in
            guard
                furniture != lastSandboxFurniture[actor],
                request.usesSpecialFurniture || !world.furnitureIsSpecial(furniture),
                let seats = world.furnitureSeats(of: furniture)
            else { return nil }
            let usable = seats.map { seat in
                var usable = seat
                usable.isEnabled = seat.isEnabled && request.admits(seat)
                return usable
            }
            guard
                let distance = usable.filter(\.isEnabled)
                    .map({ simd_distance($0.position, near) }).min(),
                world.furnitureOwnerAllows(actor, furniture)
            else { return nil }
            return SandboxCandidate(furniture: furniture, seats: usable, distance: distance)
        }
        let traits = world.furnitureActorTraits(actor)
        for candidate in candidates.sorted(by: { $0.distance < $1.distance }) {
            let seat = ledger.reserve(
                in: candidate.furniture, seats: candidate.seats, actor: actor,
                near: near, traits: traits
            ) { world.furnitureActorHasKeyword(actor, $0) }
            if let seat {
                lastSandboxFurniture[actor] = candidate.furniture
                return seat
            }
        }
        return nil
    }
}

private struct SandboxCandidate {
    let furniture: ReferenceKey
    let seats: [FurnitureSeat]
    let distance: Float
}
