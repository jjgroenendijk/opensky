// The vehicle shell returns the poses it solved as commands: a rider placed on its
// carrier each frame, a rest pose when it leaves, and one clear after the last link.
// Each way a link ends has a test: `SetVehicle(None)`, `SetVehicle(self)`, `ExitCartEnd`,
// and a horse rider's package ending.

@testable import OpenSkyActorPresentation
@testable import OpenSkyFormatsESM
import OpenSkyWorldState
import simd
import Testing

@MainActor
private final class FakeVehicleWorld: VehicleWorld {
    var poses: [ReferenceKey: ReferenceTransformOverride] = [:]

    func vehiclePose(of key: ReferenceKey) -> ReferenceTransformOverride? {
        poses[key]
    }

    func vehicleFormID(of _: ReferenceKey) -> UInt32? {
        nil
    }

    func vehicleBone(of _: ReferenceKey, named _: String) -> SIMD3<Float>? {
        nil
    }

    func vehicleGround(at _: SIMD3<Float>, excluding _: Set<ReferenceKey>) -> Float? {
        nil
    }

    func vehicleWheels(of _: ReferenceKey) -> [SIMD2<Float>]? {
        nil
    }
}

@MainActor
struct VehicleCoordinatorTests {
    private let cart = ReferenceKey.plugin(name: "test.esp", objectID: 0x20)

    @Test func aBoardedPlayerIsPlacedOnTheCarrier() throws {
        let world = FakeVehicleWorld()
        world.poses[cart] = ReferenceTransformOverride(position: SIMD3(10, 0, 0))
        let vehicles = VehicleCoordinator(world: world)
        #expect(vehicles.board(.player, on: cart))

        let commands = vehicles.advance()

        let seat = try #require(vehicles.lastPoses[.player])
        #expect(seat.position == SIMD3(10, 0, 0))
        #expect(commands == [
            .placePlayer(seat),
            .publishVehiclePoses([:]),
            .publishCarriedPoses([:]),
            .publishLinks([.player, cart])
        ])
    }

    @Test func leavingRestsTheRiderAndTheNextFrameClearsOnce() throws {
        let world = FakeVehicleWorld()
        world.poses[cart] = ReferenceTransformOverride(position: SIMD3(10, 0, 0))
        let vehicles = VehicleCoordinator(world: world)
        vehicles.board(.player, on: cart)
        _ = vehicles.advance()
        let seat = try #require(vehicles.lastPoses[.player])

        #expect(vehicles.detach(.player) == [.followerRests(.player, at: seat)])
        #expect(vehicles.detach(.player).isEmpty)
        #expect(vehicles.advance() == [
            .publishVehiclePoses([:]), .publishCarriedPoses([:]), .publishLinks([])
        ])
        #expect(vehicles.advance().isEmpty)
    }

    private let rider = ReferenceKey.plugin(name: "test.esp", objectID: 0x21)

    /// A rider seated on the cart, with the pose it had in its last frame there.
    private func seatedRider() throws -> (VehicleCoordinator, ReferenceTransformOverride) {
        let world = FakeVehicleWorld()
        world.poses[cart] = ReferenceTransformOverride(position: SIMD3(10, 0, 0))
        let vehicles = VehicleCoordinator(world: world)
        #expect(vehicles.setVehicle(rider, vehicle: cart).isEmpty)
        _ = vehicles.advance()
        return try (vehicles, #require(vehicles.lastPoses[rider]))
    }

    @Test func setVehicleNoneTakesTheRiderOff() throws {
        let (vehicles, seat) = try seatedRider()
        #expect(vehicles.setVehicle(rider, vehicle: nil) == [.followerRests(rider, at: seat)])
        #expect(vehicles.core.links[rider] == nil)
    }

    @Test func setVehicleOnItselfTakesTheRiderOff() throws {
        let (vehicles, seat) = try seatedRider()
        #expect(vehicles.setVehicle(rider, vehicle: rider) == [.followerRests(rider, at: seat)])
        #expect(vehicles.core.links[rider] == nil)
    }

    @Test func theCartExitEndTakesTheRiderOff() throws {
        let (vehicles, seat) = try seatedRider()
        #expect(vehicles.animationEvent("ExitCartBegin", from: rider).isEmpty)
        #expect(vehicles.core.links[rider]?.carrier == cart)
        #expect(vehicles.animationEvent("exitcartend", from: rider) == [.followerRests(
            rider,
            at: seat
        )])
        #expect(vehicles.core.links[rider] == nil)
    }

    @Test func theCartExitEndOfAnActorOnNoVehicleDoesNothing() {
        let vehicles = VehicleCoordinator(world: FakeVehicleWorld())
        #expect(vehicles.animationEvent("ExitCartEnd", from: rider).isEmpty)
    }

    /// The AI drops a horse rider when its package ends, through `detach`.
    @Test func aPackageEndTakesTheHorseRiderOff() throws {
        let world = FakeVehicleWorld()
        world.poses[cart] = ReferenceTransformOverride(position: SIMD3(0, 5, 0))
        let vehicles = VehicleCoordinator(world: world)
        #expect(vehicles.seat(rider, on: cart, bone: "SaddleBone"))
        _ = vehicles.advance()
        let saddle = try #require(vehicles.lastPoses[rider])
        #expect(vehicles.detach(rider) == [.followerRests(rider, at: saddle)])
        #expect(vehicles.core.mounts.isEmpty)
    }
}
