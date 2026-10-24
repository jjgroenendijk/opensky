// The furniture seats every actor shares. A package or the player reserves a
// marker, sits in it, and stands up from it; the world places the actor, plays its
// idles, and tells the scripts. See docs/engine/furniture.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyWorldInterface
import simd

/// What the furniture coordinator reads from the world and asks of it. The app answers it.
@MainActor
public protocol FurnitureWorld: AnyObject {
    /// The seats of a loaded furniture reference, in marker order; nil when it is not loaded.
    func furnitureSeats(of furniture: ReferenceKey) -> [FurnitureSeat]?
    func furnitureActorPosition(_ actor: ReferenceKey) -> SIMD3<Float>?
    /// Whether the actor's base has the keyword (`KWDA`).
    func furnitureActorHasKeyword(_ actor: ReferenceKey, _ keyword: FormID) -> Bool
    func furnitureActorTraits(_ actor: ReferenceKey) -> FurnitureActorTraits
    /// A crafting station or other furniture a sandbox uses only with Allow Special Furniture.
    func furnitureIsSpecial(_ furniture: ReferenceKey) -> Bool
    /// False when someone other than the actor or its faction owns the furniture.
    func furnitureOwnerAllows(_ actor: ReferenceKey, _ furniture: ReferenceKey) -> Bool
    /// Sets the actor on the seat, starts its entry idle, and tells the scripts.
    func placeSeated(_ actor: ReferenceKey, in occupancy: FurnitureOccupancy)
    /// Starts the exit idle and tells the scripts.
    func placeStanding(_ actor: ReferenceKey, from occupancy: FurnitureOccupancy)
    /// Whether the actor's exit idle still loads; it stays on the seat until it plays.
    func furnitureExitIsLoading(_ actor: ReferenceKey) -> Bool
    /// The root motion of the entry or exit clip the actor plays now, if it has one.
    func furnitureMotion(of actor: ReferenceKey) -> FurnitureMotionSample?
    /// Sets the actor's root on its way into, on, or out of a seat.
    func moveFurnitureActor(_ actor: ReferenceKey, to pose: FurniturePose)
    /// The exit is over: the actor stands at `pose` and walks again.
    func finishStanding(_ actor: ReferenceKey, at pose: FurniturePose)
    /// The loaded furniture references.
    func residentFurniture() -> [ReferenceKey]
    /// Turns the seated player's first-person view to `yaw` radians.
    func turnSeatedPlayerView(toYaw yaw: Float)
}

/// One actor in one seat.
nonisolated public struct FurnitureOccupancy: Equatable, Sendable {
    public let seat: PackageSeat
    /// The side the actor came in by: 1 front, 2 behind, 4 right, 8 left, 16 up.
    public let entry: UInt16

    public init(seat: PackageSeat, entry: UInt16) {
        self.seat = seat
        self.entry = entry
    }
}

/// Why an actor could not use a piece of furniture.
nonisolated public enum FurnitureUseRefusal: String, Error, Equatable, Sendable {
    /// The launcher switch is off.
    case disabled
    case notLoaded
    case noSeats
    case noFreeSeat
    case alreadySeated
}

@MainActor
public final class FurnitureCoordinator {
    public internal(set) var ledger = FurnitureSeatLedger()
    public private(set) var occupancies: [ReferenceKey: FurnitureOccupancy] = [:]
    /// Actors whose exit clip still carries them out of the seat they left.
    public private(set) var exits: [ReferenceKey: FurnitureOccupancy] = [:]
    /// Seated actors that an entry clip still moves.
    private var entering: Set<ReferenceKey> = []
    /// The furniture each sandboxing actor used last, which its next choice skips.
    var lastSandboxFurniture: [ReferenceKey: ReferenceKey] = [:]
    /// The launcher switch. Off, no actor sits down; an actor already seated may still stand.
    public var isEnabled = true
    /// `Game.SetSittingRotation`, in degrees. It lasts until the player stands up.
    public private(set) var sittingRotation: Float = 0
    weak let world: (any FurnitureWorld)?

    public init(world: any FurnitureWorld) {
        self.world = world
    }

    /// Reserves a free seat of `animation` first, nearest to the actor first.
    public func reserve(
        in furniture: ReferenceKey, for actor: ReferenceKey, animation: UInt16?
    ) -> PackageSeat? {
        guard let world, let seats = world.furnitureSeats(of: furniture) else { return nil }
        return ledger.reserve(
            in: furniture, seats: seats, actor: actor, animation: animation,
            near: world.furnitureActorPosition(actor), traits: world.furnitureActorTraits(actor)
        ) { world.furnitureActorHasKeyword(actor, $0) }
    }

    /// The player's activation, or a debug command: the nearest free seat, then sit.
    public func use(
        _ furniture: ReferenceKey, by actor: ReferenceKey
    ) -> Result<FurnitureOccupancy, FurnitureUseRefusal> {
        guard isEnabled else { return .failure(.disabled) }
        guard occupancies[actor] == nil else { return .failure(.alreadySeated) }
        guard let seats = world?.furnitureSeats(of: furniture) else { return .failure(.notLoaded) }
        guard seats.contains(where: \.isEnabled) else { return .failure(.noSeats) }
        guard
            let seat = reserve(in: furniture, for: actor, animation: nil),
            let occupancy = sit(actor, in: seat)
        else { return .failure(.noFreeSeat) }
        return .success(occupancy)
    }

    /// Sits the actor in a seat it reserved. Nil, and the seat freed, while the switch is off.
    @discardableResult
    public func sit(_ actor: ReferenceKey, in seat: PackageSeat) -> FurnitureOccupancy? {
        guard isEnabled else {
            ledger.release(seat, by: actor)
            return nil
        }
        if let current = occupancies[actor] {
            guard current.seat != seat else { return current }
            stand(actor)
            ledger.hold(seat, by: actor)
        }
        let approach = world?.furnitureActorPosition(actor) ?? seat.seat.position
        let occupancy = FurnitureOccupancy(seat: seat, entry: seat.seat.entry(from: approach))
        occupancies[actor] = occupancy
        exits[actor] = nil
        world?.placeSeated(actor, in: occupancy)
        if actor == .player {
            turnPlayerView(occupancy)
        }
        return occupancy
    }

    /// Frees every seat the actor holds or reserved and starts its exit. `advance` carries
    /// it out of the seat.
    @discardableResult
    public func stand(_ actor: ReferenceKey) -> Bool {
        guard let occupancy = vacate(actor) else { return false }
        exits[actor] = occupancy
        world?.placeStanding(actor, from: occupancy)
        advance()
        return true
    }

    /// Moves each actor along the root motion of its entry or exit clip, and ends each
    /// exit whose clip is done. The player is placed every frame.
    public func advance() {
        guard let world else { return }
        for (actor, occupancy) in exits {
            let seat = occupancy.seat.seat
            guard let sample = world.furnitureMotion(of: actor) else {
                if world.furnitureExitIsLoading(actor) {
                    world.moveFurnitureActor(actor, to: seat.seatedPose)
                    continue
                }
                exits[actor] = nil
                world.finishStanding(actor, at: seat.standingPose(entry: occupancy.entry))
                continue
            }
            if sample.isFinished {
                exits[actor] = nil
                world.finishStanding(actor, at: seat.leavingPose(sample))
            } else {
                world.moveFurnitureActor(actor, to: seat.leavingPose(sample))
            }
        }
        for (actor, occupancy) in occupancies {
            let seat = occupancy.seat.seat
            let sample = world.furnitureMotion(of: actor)
            // The last entry frame goes back on the seat itself.
            guard sample != nil || entering.contains(actor) || actor == .player else { continue }
            world.moveFurnitureActor(actor, to: sample.map(seat.enteringPose) ?? seat.seatedPose)
            if sample == nil {
                entering.remove(actor)
            } else {
                entering.insert(actor)
            }
        }
    }

    /// The player greets `actor`. A seat whose furniture is Must Exit To Talk lets it up
    /// (Creation Kit wiki "Furniture").
    @discardableResult
    public func greet(_ actor: ReferenceKey) -> Bool {
        guard actor != .player, occupancies[actor]?.seat.seat.rules.mustExitToTalk == true else {
            return false
        }
        return stand(actor)
    }

    /// Whether an exit clip still carries the actor, so nothing else should move it.
    public func isLeavingSeat(_ actor: ReferenceKey) -> Bool {
        exits[actor] != nil
    }

    /// Forgets the actor's seat and reservations without standing it up, for an actor
    /// that something else moved away, such as a teleport.
    @discardableResult
    public func vacate(_ actor: ReferenceKey) -> FurnitureOccupancy? {
        ledger.releaseAll(heldBy: actor)
        exits[actor] = nil
        entering.remove(actor)
        if actor == .player {
            sittingRotation = 0
        }
        return occupancies.removeValue(forKey: actor)
    }

    /// Frees the seats the actor reserved but does not sit in.
    public func releaseReservations(of actor: ReferenceKey) {
        ledger.releaseAll(heldBy: actor)
        if let kept = occupancies[actor]?.seat {
            ledger.hold(kept, by: actor)
        }
    }

    /// Whether an actor holds `marker`, or any marker when nil. A reserved marker whose
    /// actor has not sat down yet counts only without `ignoringReserved`.
    public func isInUse(_ furniture: ReferenceKey, marker: Int?, ignoringReserved: Bool) -> Bool {
        let holders = ledger.holders(of: furniture)
        let markers = marker.map { [$0] } ?? Array(holders.keys)
        return markers.contains { index in
            guard let actor = holders[index] else { return false }
            guard ignoringReserved else { return true }
            let seat = occupancies[actor]?.seat
            return seat?.furniture == furniture && seat?.index == index
        }
    }

    public func setSittingRotation(degrees: Float) {
        sittingRotation = degrees
        if let occupancy = occupancies[.player] {
            turnPlayerView(occupancy)
        }
    }

    /// The loaded furniture with a free seat for the actor, nearest seat first.
    public func nearestFurniture(to actor: ReferenceKey) -> ReferenceKey? {
        guard let world, let position = world.furnitureActorPosition(actor) else { return nil }
        let candidates = world.residentFurniture().compactMap { furniture -> (
            ReferenceKey,
            Float
        )? in
            guard let seats = world.furnitureSeats(of: furniture) else { return nil }
            let holders = ledger.holders(of: furniture)
            let free = seats.indices.filter {
                seats[$0].isEnabled && (holders[$0] == nil || holders[$0] == actor)
            }
            guard let nearest = free.map({ simd_distance(seats[$0].position, position) }).min()
            else { return nil }
            return (furniture, nearest)
        }
        return candidates.min { $0.1 < $1.1 }?.0
    }

    /// Negative degrees look left, which is a larger counter-clockwise yaw.
    private func turnPlayerView(_ occupancy: FurnitureOccupancy) {
        let offset = sittingRotation * .pi / 180
        world?.turnSeatedPlayerView(toYaw: occupancy.seat.seat.facingYaw - offset)
    }
}
