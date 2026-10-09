// The vehicle rules: a follower keeps its offset to the carrier, chains
// compose, and a link that would make a loop is refused.

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
        let poses = core.poses { _ in ReferenceTransformOverride(position: [100, 50, 10]) }
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
        let poses = core.poses { _ in turned }
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
        let poses = core.poses { $0 == Self.horse ? moved : nil }
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
}
