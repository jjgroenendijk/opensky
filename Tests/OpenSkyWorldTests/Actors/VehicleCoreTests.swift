// The vehicle rules: a follower keeps its offset to the carrier, a towed cart
// trails its horse, chains compose, and a link that would make a loop is refused.

@testable import OpenSkyFormatsESM
@testable import OpenSkyWorld
import OpenSkyWorldState
import simd
import Testing

struct VehicleCoreTests {
    private static let horse = ReferenceKey.plugin(name: "test.esm", objectID: 1)
    private static let cart = ReferenceKey.plugin(name: "test.esm", objectID: 2)

    private static func near(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> Bool {
        simd_length(lhs - rhs) < 0.01
    }

    @Test func aFollowerKeepsItsOffsetWhenTheCarrierMoves() throws {
        var core = VehicleCore()
        core.attach(
            Self.cart, to: Self.horse,
            followerPose: ReferenceTransformOverride(position: [0, -200, 0]),
            carrierPose: ReferenceTransformOverride(position: .zero)
        )
        let poses = core.advance(base: { _ in ReferenceTransformOverride(position: [100, 50, 10]) })
        let cart = try #require(poses[Self.cart])
        #expect(Self.near(cart.position, [100, -150, 10]))
    }

    @Test func aFollowerTurnsWithTheCarrier() throws {
        var core = VehicleCore()
        core.attach(
            Self.cart, to: Self.horse,
            followerPose: ReferenceTransformOverride(position: [0, -200, 0]),
            carrierPose: ReferenceTransformOverride(position: .zero)
        )
        let turned = ReferenceTransformOverride(position: .zero, rotation: [0, 0, .pi / 2])
        let poses = core.advance(base: { _ in turned })
        let cart = try #require(poses[Self.cart])
        #expect(Self.near(cart.position, [200, 0, 0]) || Self.near(cart.position, [-200, 0, 0]))
        #expect(abs(abs(cart.rotation.z) - .pi / 2) < 0.01)
    }

    @Test func aRiderOnACartFollowsTheHorse() throws {
        var core = VehicleCore()
        let origin = ReferenceTransformOverride(position: .zero)
        core.attach(Self.cart, to: Self.horse, followerPose: origin, carrierPose: origin)
        core.attach(
            .player, to: Self.cart,
            followerPose: ReferenceTransformOverride(position: [0, 0, 50]), carrierPose: origin
        )
        let moved = ReferenceTransformOverride(position: [10, 0, 0])
        let poses = core.advance(base: { $0 == Self.horse ? moved : nil })
        let rider = try #require(poses[.player])
        #expect(Self.near(rider.position, [10, 0, 50]))
    }

    @Test func aLoopIsRefused() {
        var core = VehicleCore()
        let origin = ReferenceTransformOverride(position: .zero)
        let attached = core.attach(
            Self.cart,
            to: Self.horse,
            followerPose: origin,
            carrierPose: origin
        )
        let looped = core.attach(
            Self.horse,
            to: Self.cart,
            followerPose: origin,
            carrierPose: origin
        )
        let toItself = core.attach(
            Self.cart,
            to: Self.cart,
            followerPose: origin,
            carrierPose: origin
        )
        #expect(attached)
        #expect(!looped)
        #expect(!toItself)
        core.detach(Self.cart)
        #expect(core.links.isEmpty)
    }

    @Test func aRiderBoardsOnTheVehicleRoot() throws {
        var core = VehicleCore()
        core.board(.player, on: Self.cart)
        let poses = core.advance(base: { _ in ReferenceTransformOverride(position: [100, 50, 10]) })
        #expect(try Self.near(#require(poses[.player]).position, [100, 50, 10]))
    }

    @Test func aRiderSitsOnTheLiveSaddleBone() throws {
        var core = VehicleCore()
        core.seat(.player, on: Self.horse, bone: "SaddleBone")
        var saddle = SIMD3<Float>(0, 10, 120)
        let horse = ReferenceTransformOverride(position: [100, 0, 0])
        var poses = core.advance(base: { _ in horse }, bone: { _, _ in saddle })
        #expect(try Self.near(#require(poses[.player]).position, [100, 10, 120]))
        saddle.z = 125
        poses = core.advance(base: { _ in horse }, bone: { _, _ in saddle })
        #expect(try Self.near(#require(poses[.player]).position, [100, 10, 125]))
    }

    /// A cart 200 units behind its horse, on flat ground at height 0.
    private static func towedCart() -> VehicleCore {
        var core = VehicleCore()
        core.tow(
            Self.cart, by: Self.horse,
            followerPose: ReferenceTransformOverride(position: [0, -200, 0]),
            carrierPose: ReferenceTransformOverride(position: .zero),
            ground: { _ in 0 }
        )
        return core
    }

    @Test func aTowedCartTrailsItsHorseAtTheSameDistance() throws {
        var core = Self.towedCart()
        let ahead = ReferenceTransformOverride(position: [0, 100, 0])
        let poses = core.advance(base: { _ in ahead }, ground: { _ in 0 })
        #expect(try Self.near(#require(poses[Self.cart]).position, [0, -100, 0]))
    }

    @Test func aTowedCartDoesNotSwingWhenTheHorseTurnsInPlace() throws {
        var core = Self.towedCart()
        let turned = ReferenceTransformOverride(position: .zero, rotation: [0, 0, .pi / 4])
        let poses = core.advance(base: { _ in turned }, ground: { _ in 0 })
        #expect(try Self.near(#require(poses[Self.cart]).position, [0, -200, 0]))
    }

    @Test func aTowedCartTurnsToFaceItsHorse() throws {
        var core = Self.towedCart()
        let side = ReferenceTransformOverride(position: [200, -200, 0])
        let cart = try #require(
            core.advance(base: { _ in side }, ground: { _ in 0 })[Self.cart]
        )
        #expect(Self.near(cart.position, [0, -200, 0]))
        // Clockwise yaw: a quarter turn faces +X.
        #expect(abs(cart.rotation.z - .pi / 2) < 0.01)
    }

    @Test func aTowedCartSitsOnTheGroundAndTilts() throws {
        var core = Self.towedCart()
        let ahead = ReferenceTransformOverride(position: [0, 100, 50])
        let slope: (SIMD2<Float>) -> Float? = { $0.y / 4 }
        let cart = try #require(core.advance(base: { _ in ahead }, ground: slope)[Self.cart])
        #expect(Self.near(cart.position, [0, -100, -25]))
        #expect(abs(abs(cart.rotation.x) - atan2(50, 200)) < 0.01)
    }

    @Test func aRiderOnATowedCartFollowsTheCart() throws {
        var core = Self.towedCart()
        core.board(.player, on: Self.cart)
        let ahead = ReferenceTransformOverride(position: [0, 100, 0])
        let poses = core.advance(base: { $0 == Self.horse ? ahead : nil }, ground: { _ in 0 })
        #expect(try Self.near(#require(poses[.player]).position, [0, -100, 0]))
    }
}
