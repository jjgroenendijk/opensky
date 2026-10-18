// The vehicle shell returns the poses it solved as commands: a rider placed on its
// carrier each frame, a rest pose when it leaves, and one clear after the last link.

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
}
