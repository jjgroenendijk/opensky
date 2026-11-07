// A horse's skeleton bound gives two end spheres; a human's gives none. The ends stop a
// long body's nose and tail at a box its centre capsule would walk past.

import OpenSkyEngineTesting
@testable import OpenSkyPhysics
import simd
import Testing

struct LongBodyShapeTests {
    private static let horse = SIMD3<Float>(31.82, 103.29, 84.52)

    @Test
    func aHorseHasTwoEndSpheres() throws {
        let shape = try #require(LongBodyShape(halfExtents: Self.horse))
        #expect(shape.isForwardLong)
        #expect(abs(shape.endRadius - 52.7) < 0.01)
        #expect(abs(shape.endOffset - (103.29 - 31.82 - 8)) < 0.01)
    }

    @Test
    func anUprightBodyHasNone() {
        #expect(LongBodyShape(halfExtents: SIMD3(22, 14, 64)) == nil)
        #expect(LongBodyShape(halfExtents: SIMD3(30, 40, 35)) == nil)
    }

    @Test
    func theEndsFollowTheYaw() throws {
        let shape = try #require(LongBodyShape(halfExtents: Self.horse))
        let ends = shape.endFeet(at: .zero, yaw: .pi / 2, lift: 32)
        #expect(abs(ends[0].y - shape.endOffset) < 0.001 && abs(ends[0].x) < 0.001)
        #expect(abs(ends[1].y + shape.endOffset) < 0.001 && ends[1].z == 32)
    }

    @Test
    func aBoxAheadStopsTheNose() throws {
        let shape = try #require(LongBodyShape(halfExtents: Self.horse))
        // The box face is 100 units ahead: the nose sphere reaches 63.5 + 52.7.
        let box = DynamicBodyScene.box(center: SIMD3(150, 0, 80), half: SIMD3(50, 50, 80))
        let correction = shape.correction(
            feet: .zero, yaw: 0, displacement: SIMD2(10, 0), lift: 32,
            query: DynamicBodyScene.candidateQuery([box])
        )
        #expect(correction.x < -10, "correction \(correction)")
        let clear = shape.correction(
            feet: SIMD3(-200, 0, 0), yaw: 0, displacement: SIMD2(10, 0), lift: 32,
            query: DynamicBodyScene.candidateQuery([box])
        )
        #expect(simd_length(clear) < 0.01)
    }
}
