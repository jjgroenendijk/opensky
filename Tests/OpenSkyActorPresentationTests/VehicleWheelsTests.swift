// A towed cart rests on the ground under its wheels: all of them touch on a slope,
// a change of slope, or a side slope, and none sinks below the ground.

@testable import OpenSkyActorPresentation
import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyWorldState
import simd
import Testing

struct VehicleWheelsTests {
    private static let horse = ReferenceKey.plugin(name: "test.esm", objectID: 1)
    private static let cart = ReferenceKey.plugin(name: "test.esm", objectID: 2)
    /// The prisoner carriage's layout: the front axle at the origin, the back one behind.
    private static let wheels: [SIMD2<Float>] = [[-73, 0], [74, 0], [-72, -215], [74, -215]]

    /// A cart 200 units behind its horse, after the horse walked 100 units on.
    private static func pulledCart(
        wheels: [SIMD2<Float>] = wheels, ground: @escaping (SIMD3<Float>) -> Float?
    ) throws -> float4x4 {
        var core = VehicleCore()
        core.tow(
            cart, by: horse,
            followerPose: ReferenceTransformOverride(position: [0, -200, 0]),
            carrierPose: ReferenceTransformOverride(position: .zero),
            ground: ground
        )
        core.setWheels(wheels, for: cart)
        let ahead = ReferenceTransformOverride(position: [0, 100, 0])
        let pose = try #require(core.advance(base: { _ in ahead }, ground: ground)[cart])
        return VehicleCore.matrix(pose)
    }

    /// How far each wheel's contact point is above the ground.
    private static func gaps(
        _ pose: float4x4, _ ground: (SIMD3<Float>) -> Float?
    ) -> [Float] {
        wheels.map { wheel in
            let contact = pose * SIMD4(wheel.x, wheel.y, 0, 1)
            return contact.z - (ground(SIMD3(contact.x, contact.y, 1000)) ?? 0)
        }
    }

    @Test func everyWheelTouchesAChangeOfSlope() throws {
        // Flat under the front axle, rising behind it.
        let ground: (SIMD3<Float>) -> Float? = { $0.y < -150 ? (-150 - $0.y) * 0.2 : 0 }
        let pose = try Self.pulledCart(ground: ground)
        for gap in Self.gaps(pose, ground) {
            #expect(abs(gap) < 1)
        }
    }

    @Test func everyWheelTouchesASideSlope() throws {
        let ground: (SIMD3<Float>) -> Float? = { $0.x * 0.1 }
        let pose = try Self.pulledCart(ground: ground)
        for gap in Self.gaps(pose, ground) {
            #expect(abs(gap) < 1)
        }
    }

    @Test func noWheelSinksIntoABump() throws {
        let ground: (SIMD3<Float>) -> Float? = { $0.x < 0 && $0.y < -250 ? 10 : 0 }
        let pose = try Self.pulledCart(ground: ground)
        for gap in Self.gaps(pose, ground) {
            #expect(gap > -0.01)
        }
    }

    @Test func wheelsOnOneLineFallBackToTheOrigin() throws {
        let pose = try Self.pulledCart(wheels: [[0, 0], [0, -215]], ground: { _ in 5 })
        #expect(abs(pose.columns.3.z - 5) < 0.01)
    }

    @Test func wheelContactsComeFromTheWheelNodes() throws {
        let file = try NIFFile(data: NIFFixture.file(
            blocks: [
                .init("NiNode", NIFFixture.niNode(children: [1, 2])),
                .init("NiNode", NIFFixture.niNode(
                    prefix: NIFFixture.avObjectPrefix(nameIndex: 0, translation: [0, 0, 50]),
                    children: [3]
                )),
                .init("NiNode", NIFFixture.niNode(
                    prefix: NIFFixture.avObjectPrefix(nameIndex: 1, translation: [-70, -215, 58])
                )),
                .init("NiNode", NIFFixture.niNode(
                    prefix: NIFFixture.avObjectPrefix(nameIndex: 2, translation: [80, 1, -4])
                ))
            ],
            strings: ["FrontBar", "WheelBackLeft", "WheelFrontRight"]
        ))
        #expect(try VehicleWheels.contacts(in: file) == [[-70, -215], [80, 1]])
    }

    @Test func theCartCountsHowFarItRolled() {
        var core = VehicleCore()
        core.tow(
            Self.cart, by: Self.horse,
            followerPose: ReferenceTransformOverride(position: [0, -200, 0]),
            carrierPose: ReferenceTransformOverride(position: .zero)
        )
        let ahead = ReferenceTransformOverride(position: [0, 100, 0])
        _ = core.advance(base: { _ in ahead })
        guard case let .towed(tow)? = core.links[Self.cart]?.seat else {
            Issue.record("the cart is not towed")
            return
        }
        #expect(abs(tow.rolled - 100) < 0.01)
    }

    @Test func aWheelTurnsByTheArcItRolled() throws {
        let file = try NIFFile(data: NIFFixture.file(
            blocks: [
                .init("NiNode", NIFFixture.niNode(children: [1])),
                .init("NiNode", NIFFixture.niNode(
                    prefix: NIFFixture.avObjectPrefix(nameIndex: 0, translation: [-70, -215, 50])
                ))
            ],
            strings: ["WheelBackLeft"]
        ))
        let rig = try #require(try VehicleWheelRig(file: file))
        #expect(rig.skeleton.boneNames == ["WheelBackLeft"])
        let quarter = try #require(rig.pose(rolled: .pi * 50 / 2).first)
        #expect(quarter.translation == [-70, -215, 50])
        // Rolling forward along +Y carries the top of the wheel forward.
        let top = quarter.rotation.act(SIMD3(0, 0, 1))
        #expect(simd_length(top - SIMD3(0, 1, 0)) < 0.001)
    }

    @Test func aModelWithoutWheelsHasNoRig() throws {
        let file = try NIFFile(data: NIFFixture.file(blocks: [.init(
            "NiNode",
            NIFFixture.niNode()
        )]))
        #expect(try VehicleWheelRig(file: file) == nil)
    }
}
