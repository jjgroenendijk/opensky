// Body against body contacts: two hulls meet by face clipping or at crossed edges,
// two capsules at their closest points.

import OpenSkyEngineTesting
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyPhysics
import simd
import Testing

struct DynamicConvexManifoldTests {
    private static func pair(_ first: DynamicBody, _ second: DynamicBody) -> [DynamicContact] {
        DynamicBodyContacts.pairContacts(
            first: DynamicPairBody(body: first, index: 0),
            second: DynamicPairBody(body: second, index: 1)
        )
    }

    @Test
    func aBoxOnABoxTouchesAtTheFourCornersOfTheSmallerFace() {
        let lower = DynamicBodyScene.cube(key: .generated(1), center: .zero, half: 20)
        let upper = DynamicBodyScene.cube(
            key: .generated(2), center: SIMD3(3, -2, 29.5), half: 10
        )
        let contacts = Self.pair(lower, upper)
        #expect(contacts.count == 4)
        for contact in contacts {
            #expect(contact.normal.z > 0.99, "the lower box's top face gives the normal")
            #expect(contact.body == 1, "the upper box is pushed")
            #expect(abs(contact.point.z - 20) < 0.01, "points lie on the top face")
            #expect(abs(contact.depth - (DynamicBodyContacts.contactMargin + 0.5)) < 0.01)
        }
        let xs = Set(contacts.map { Int($0.point.x.rounded()) })
        #expect(xs == [-7, 13], "the upper box's corners, clipped to nothing")
    }

    @Test
    func aBoxHangingOverAnEdgeIsClippedToTheLowerFace() {
        let lower = DynamicBodyScene.cube(key: .generated(1), center: .zero, half: 20)
        let upper = DynamicBodyScene.cube(
            key: .generated(2), center: SIMD3(25, 0, 29.5), half: 10
        )
        let contacts = Self.pair(lower, upper)
        #expect(contacts.count == 4)
        #expect(contacts.allSatisfy { $0.point.x <= 20.001 && $0.point.x >= 14.999 })
    }

    @Test
    func crossedEdgesTouchAtOnePoint() throws {
        let tilt = simd_quatf(angle: .pi / 4, axis: SIMD3(1, 0, 0))
        let lower = DynamicBodyScene.cube(
            key: .generated(1), center: .zero, half: 10, orientation: tilt
        )
        let spin = simd_quatf(angle: .pi / 4, axis: SIMD3(0, 1, 0))
        let edgeHeight = 10 * Float(2).squareRoot()
        let upper = DynamicBodyScene.cube(
            key: .generated(2), center: SIMD3(0, 0, 2 * edgeHeight - 0.5), half: 10,
            orientation: spin
        )
        let contacts = Self.pair(lower, upper)
        let contact = try #require(contacts.first)
        #expect(contacts.count == 1)
        #expect(contact.normal.z > 0.99)
        #expect(simd_length(contact.point - SIMD3(0, 0, edgeHeight)) < 0.5)
    }

    @Test
    func separatedBoxesDoNotTouch() {
        let lower = DynamicBodyScene.cube(key: .generated(1), center: .zero, half: 10)
        let upper = DynamicBodyScene.cube(key: .generated(2), center: SIMD3(0, 0, 25), half: 10)
        #expect(Self.pair(lower, upper).isEmpty)
    }

    @Test
    func crossedCapsulesTouchAtTheirClosestPoints() throws {
        let definition = { (axis: SIMD3<Float>) in
            DynamicBodyDefinition(
                volumes: [.radial(first: -axis * 20, second: axis * 20, radius: 3)], mass: 5
            )
        }
        let lower = DynamicBody(
            key: .generated(1), reference: FormID(0x100), cell: .interior(FormID(0x10)),
            definition: definition(SIMD3(1, 0, 0)), originPosition: .zero,
            orientation: .identityRotation
        )
        let upper = DynamicBody(
            key: .generated(2), reference: FormID(0x101), cell: .interior(FormID(0x10)),
            definition: definition(SIMD3(0, 1, 0)), originPosition: SIMD3(5, 3, 5.5),
            orientation: .identityRotation
        )
        let contacts = Self.pair(lower, upper)
        let contact = try #require(contacts.first)
        #expect(contacts.count == 1)
        #expect(contact.normal.z < -0.99, "the lower capsule is pushed down")
        #expect(simd_length(contact.point - SIMD3(5, 0, 2.5)) < 0.01)
    }
}

extension SIMD3 where Scalar == Float {
    fileprivate var xy: SIMD2<Float> {
        SIMD2(x, y)
    }
}
