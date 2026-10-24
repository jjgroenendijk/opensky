// FurnitureCoordinator: the player and packages share one set of seats; standing
// frees them, and `IsFurnitureInUse` tells a reserved seat from a used one.

@testable import OpenSkyAIPackages
import OpenSkyFormatsESM
import OpenSkyWorldInterface
import simd
import Testing

@MainActor
private final class FakeFurnitureWorld: FurnitureWorld {
    var seats: [ReferenceKey: [FurnitureSeat]] = [:]
    var positions: [ReferenceKey: SIMD3<Float>] = [:]
    var seated: [ReferenceKey: FurnitureOccupancy] = [:]
    var stoodAt: [ReferenceKey: SIMD3<Float>] = [:]
    var viewYaw: Float?

    func furnitureSeats(of furniture: ReferenceKey) -> [FurnitureSeat]? {
        seats[furniture]
    }

    func furnitureActorPosition(_ actor: ReferenceKey) -> SIMD3<Float>? {
        positions[actor]
    }

    func furnitureActorHasKeyword(_: ReferenceKey, _: FormID) -> Bool {
        false
    }

    func placeSeated(_ actor: ReferenceKey, in occupancy: FurnitureOccupancy) {
        seated[actor] = occupancy
    }

    func placeStanding(
        _ actor: ReferenceKey, from _: FurnitureOccupancy, at point: SIMD3<Float>
    ) {
        seated[actor] = nil
        stoodAt[actor] = point
    }

    func residentFurniture() -> [ReferenceKey] {
        Array(seats.keys)
    }

    func turnSeatedPlayerView(toYaw yaw: Float) {
        viewYaw = yaw
    }
}

@MainActor
struct FurnitureCoordinatorTests {
    let bench = ReferenceKey.plugin(name: "seat.esm", objectID: 10)
    let farChair = ReferenceKey.plugin(name: "seat.esm", objectID: 11)
    let farmer = ReferenceKey.plugin(name: "seat.esm", objectID: 2)

    /// A bench along x with two seats facing +y, entered from the front.
    private func world() -> FakeFurnitureWorld {
        let world = FakeFurnitureWorld()
        world.seats[bench] = [0, 100].map {
            FurnitureSeat(
                position: [$0, 0, 0], heading: 0, animationType: 1, keyword: nil, entryPoints: 1
            )
        }
        world.seats[farChair] = [FurnitureSeat(
            position: [0, 2000, 0], heading: 0, animationType: 1, keyword: nil, entryPoints: 1
        )]
        world.positions[.player] = [90, 30, 0]
        world.positions[farmer] = [0, 30, 0]
        return world
    }

    @Test func thePlayerTakesTheNearestFreeSeatAndStandsUpInFront() throws {
        let world = world()
        let furniture = FurnitureCoordinator(world: world)
        let occupancy = try furniture.use(bench, by: .player).get()
        #expect(occupancy.seat.index == 1)
        #expect(occupancy.entry == 1)
        #expect(world.seated[.player] == occupancy)
        #expect(abs((world.viewYaw ?? 0) - .pi / 2) < 0.0001)
        #expect(furniture.use(bench, by: .player) == .failure(.alreadySeated))

        #expect(furniture.stand(.player))
        #expect(world.stoodAt[.player] == [100, FurnitureSeat.standDistance, 0])
        #expect(!furniture.isInUse(bench, marker: nil, ignoringReserved: false))
        #expect(!furniture.stand(.player))
    }

    @Test func aReservedSeatCountsOnlyUntilReservationsAreIgnored() throws {
        let world = world()
        let furniture = FurnitureCoordinator(world: world)
        let reserved = try #require(furniture.reserve(in: bench, for: farmer, animation: 1))
        #expect(reserved.index == 0)
        #expect(furniture.isInUse(bench, marker: 0, ignoringReserved: false))
        #expect(!furniture.isInUse(bench, marker: 0, ignoringReserved: true))
        #expect(!furniture.isInUse(bench, marker: 1, ignoringReserved: false))

        furniture.sit(farmer, in: reserved)
        #expect(furniture.isInUse(bench, marker: nil, ignoringReserved: true))
        // The player cannot take the farmer's seat, so it gets the other one.
        world.positions[.player] = [0, 30, 0]
        #expect(try furniture.use(bench, by: .player).get().seat.index == 1)
        #expect(furniture.use(farChair, by: farmer) == .failure(.alreadySeated))
    }

    @Test func leavingAPackageBeforeSittingFreesTheReservation() throws {
        let world = world()
        let furniture = FurnitureCoordinator(world: world)
        _ = try #require(furniture.reserve(in: bench, for: farmer, animation: 1))
        furniture.releaseReservations(of: farmer)
        #expect(!furniture.isInUse(bench, marker: nil, ignoringReserved: false))
    }

    @Test func theSwitchKeepsActorsStanding() throws {
        let world = world()
        let furniture = FurnitureCoordinator(world: world)
        furniture.isEnabled = false
        #expect(furniture.use(bench, by: .player) == .failure(.disabled))
        let seat = try #require(furniture.reserve(in: bench, for: farmer, animation: 1))
        #expect(furniture.sit(farmer, in: seat) == nil)
        #expect(!furniture.isInUse(bench, marker: nil, ignoringReserved: false))
        #expect(world.seated.isEmpty)
    }

    @Test func sittingRotationTurnsTheSeatedViewAndEndsWithTheSeat() throws {
        let world = world()
        let furniture = FurnitureCoordinator(world: world)
        _ = try furniture.use(bench, by: .player).get()
        furniture.setSittingRotation(degrees: -90)
        #expect(abs((world.viewYaw ?? 0) - .pi) < 0.0001)
        furniture.stand(.player)
        #expect(furniture.sittingRotation == 0)
    }

    @Test func theNearestFurnitureHasAFreeSeat() {
        let world = world()
        let furniture = FurnitureCoordinator(world: world)
        #expect(furniture.nearestFurniture(to: farmer) == bench)
        world.seats[bench] = world.seats[bench]?.map {
            var off = $0
            off.isEnabled = false
            return off
        }
        #expect(furniture.nearestFurniture(to: farmer) == farChair)
    }
}
