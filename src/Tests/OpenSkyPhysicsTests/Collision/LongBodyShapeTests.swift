// A horse's skeleton bound gives two end spheres and a body capsule along its back; a
// human's gives none. The ends stop the nose and tail, and the body stops the back.

import OpenSkyEngineTesting
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
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
        #expect(abs(shape.bodyRadius - 31.82) < 0.01)
        #expect(abs(shape.bodyHeight - (84.52 - 31.82 + 84.52)) < 0.01)
        #expect(abs(shape.bodyHalfLength - (103.29 - 31.82)) < 0.01)
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
        let body = shape.bodyBallFeet(at: .zero, yaw: .pi / 2)
        #expect(abs((body.last?.y ?? 0) - shape.bodyHalfLength) < 0.001)
        #expect(abs(ends[0].y - shape.endOffset) < 0.001 && abs(ends[0].x) < 0.001)
        #expect(abs(ends[1].y + shape.endOffset) < 0.001 && ends[1].z == 32)
    }

    @Test
    func aBoxAheadStopsTheNose() throws {
        let shape = try #require(LongBodyShape(halfExtents: Self.horse))
        // The box face is 100 units ahead: the nose sphere reaches 63.5 + 52.7.
        let box = DynamicBodyScene.box(center: SIMD3(150, 0, 80), half: SIMD3(50, 50, 80))
        let correction = shape.correction(
            pose: (.zero, 0), displacement: SIMD2(10, 0), ground: { _ in 0 },
            query: DynamicBodyScene.candidateQuery([box])
        )
        #expect(correction.x < -9.9, "correction \(correction)")
        let clear = shape.correction(
            pose: (SIMD3(-200, 0, 0), 0), displacement: SIMD2(10, 0), ground: { _ in 0 },
            query: DynamicBodyScene.candidateQuery([box])
        )
        #expect(simd_length(clear) < 0.01)
    }

    /// A beam at 110 to 120 units stops the back; the end spheres pass under it.
    @Test
    func aLowBeamStopsTheBack() throws {
        let shape = try #require(LongBodyShape(halfExtents: Self.horse))
        let beam = DynamicBodyScene.box(center: SIMD3(110, 0, 115), half: SIMD3(5, 200, 5))
        let blocked = shape.correction(
            pose: (.zero, 0), displacement: SIMD2(10, 0), ground: { _ in 0 },
            query: DynamicBodyScene.candidateQuery([beam])
        )
        #expect(blocked.x < -2, "correction \(blocked)")
        let high = DynamicBodyScene.box(center: SIMD3(110, 0, 300), half: SIMD3(5, 200, 5))
        let under = shape.correction(
            pose: (.zero, 0), displacement: SIMD2(10, 0), ground: { _ in 0 },
            query: DynamicBodyScene.candidateQuery([high])
        )
        #expect(simd_length(under) < 0.01)
    }

    /// Each end stands on the slope under it and follows it, so walking up a 15-degree
    /// slope adds no push back.
    @Test
    func aSlopeDoesNotPushTheEndsBack() throws {
        let shape = try #require(LongBodyShape(halfExtents: Self.horse))
        let angle: Float = 15 * .pi / 180
        let normal = SIMD3<Float>(-sinf(angle), 0, cosf(angle))
        var transform = simd_float4x4(simd_quatf(angle: -angle, axis: SIMD3(0, 1, 0)))
        transform.columns.3 = SIMD4(-10 * normal, 1)
        let ramp = StaticCollisionShape(
            reference: FormID(3), transform: transform, geometry: .box(halfExtents: SIMD3(
                500,
                500,
                10
            )),
            bounds: ModelBounds(min: SIMD3(-600, -600, -200), max: SIMD3(600, 600, 200))
        )
        let correction = shape.correction(
            pose: (.zero, 0), displacement: SIMD2(10, 0), ground: { $0.x * tanf(angle) },
            query: DynamicBodyScene.query([ramp])
        )
        #expect(simd_length(correction) < 0.5, "correction \(correction)")
    }

    /// A human skeleton's bound gives the game's radius 18 and height 128; scale grows both.
    @Test
    func anUprightBoundGivesTheGamesCapsule() throws {
        let human = SIMD3<Float>(22, 14, 64)
        let capsule = try #require(PlayerCapsule.upright(halfExtents: human))
        #expect(capsule.radius == 18 && capsule.height == 128 && capsule.eyeHeight == 112)
        let giant = try #require(PlayerCapsule.upright(halfExtents: human, scale: 2))
        #expect(giant.radius == 36 && giant.height == 256)
        #expect(PlayerCapsule.upright(halfExtents: Self.horse) == nil)
    }
}
