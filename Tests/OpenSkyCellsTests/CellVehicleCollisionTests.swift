// A vehicle follower's collision leaves the static set and moves with the
// vehicle, and the actors of a vehicle link do not collide with it.

@testable import OpenSkyAIPackages
@testable import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyNavigation
import OpenSkyPhysics
import simd
import Testing

struct CellVehicleCollisionTests {
    private static let cart = FormID(stored: 0x10)
    private static let rock = FormID(stored: 0x20)
    private static let placement = MatrixMath.translation([0, -200, 0])

    private static func box(_ reference: FormID, at center: SIMD3<Float>) -> StaticCollisionShape {
        StaticCollisionShape(
            reference: reference,
            transform: MatrixMath.translation(center),
            geometry: .box(halfExtents: [10, 10, 10]),
            bounds: ModelBounds(min: center - 10, max: center + 10)
        )
    }

    private static func split() -> (fixed: StaticCollisionSet, vehicles: [CellVehicleCollision]) {
        let set = StaticCollisionSet(
            location: nil,
            shapes: [box(cart, at: [0, -200, 10]), box(rock, at: [500, 0, 10])],
            stats: StaticCollisionStats()
        )
        return CellVehicleCollision.split(set, followers: [cart: placement])
    }

    @Test func aFollowersShapesLeaveTheStaticSet() {
        let split = Self.split()
        #expect(split.fixed.shapes.map(\.reference) == [Self.rock])
        #expect(split.vehicles.map(\.reference) == [Self.cart])
    }

    @Test func theShapesMoveWithTheVehicle() throws {
        let vehicle = try #require(Self.split().vehicles.first)
        let pose = MatrixMath.translation([0, 100, 0])
        let everywhere = ModelBounds(min: SIMD3(repeating: -1000), max: SIMD3(repeating: 1000))
        let moved = try #require(vehicle.shapes(at: pose, overlapping: everywhere).first)
        #expect(moved.transform.columns.3 == SIMD4(0, 100, 10, 1))
        #expect(moved.bounds.min == [-10, 90, 0])
        let oldSpot = ModelBounds(min: [-5, -205, 5], max: [5, -195, 15])
        #expect(vehicle.shapes(at: pose, overlapping: oldSpot).isEmpty)
    }

    @Test @MainActor func aLinkedActorIgnoresTheVehicles() {
        let horse = ReferenceKey.plugin(name: "test.esm", objectID: 1)
        let guardActor = ReferenceKey.plugin(name: "test.esm", objectID: 2)
        let cartShape = Self.box(Self.cart, at: .zero)
        var world = NPCMovementWorld(
            sampleGround: { _ in nil },
            collisionQuery: { _ in [cartShape] },
            repath: { _ in .miss(.disconnected) },
            cellAt: { _ in nil },
            triggersAt: { _ in [] }
        )
        world.vehicleActors = [horse]
        world.collisionQueryIgnoringVehicles = { _ in [] }
        let bounds = ModelBounds(min: SIMD3(repeating: -1), max: SIMD3(repeating: 1))
        #expect(world.collisionQuery(for: horse)(bounds).isEmpty)
        #expect(world.collisionQuery(for: guardActor)(bounds).count == 1)
    }
}
