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

    /// A skeever's nose meets a 20-unit kerb. The walk steps over it, so the ends must too;
    /// a wall taller than a step still stops them.
    @Test
    func anEndPassesWhatTheWalkStepsOver() throws {
        var shape = try #require(LongBodyShape(halfExtents: SIMD3(15.23, 62.27, 28.42)))
        let reach = shape.endOffset + shape.endRadius
        let kerb = DynamicBodyScene.box(
            center: SIMD3(reach + 51, 0, 10), half: SIMD3(50, 200, 10)
        )
        let wall = DynamicBodyScene.box(
            center: SIMD3(reach + 51, 0, 40), half: SIMD3(50, 200, 40)
        )
        func push(_ box: StaticCollisionShape) -> LongBodyPush {
            shape.largestPush(
                pose: (.zero, 0), displacement: SIMD2(5, 0), ground: { _ in 0 },
                query: DynamicBodyScene.candidateQuery([box])
            )
        }
        let stopped = push(kerb)
        #expect(stopped.added.x < -3.9 && stopped.part == .end(0), "push \(stopped)")
        shape.stepHeight = 32
        #expect(simd_length(push(kerb).added) < 0.01)
        #expect(push(wall).added.x < -3.9)
    }

    /// After a turn the tail of a skeever's back sits 3 units inside the wall behind it.
    /// It may walk away from that wall, and not deeper into it.
    @Test
    func aPartInsideAWallMayLeaveIt() throws {
        let shape = try #require(LongBodyShape(halfExtents: SIMD3(15.23, 62.27, 28.42)))
        let face = -(shape.bodyHalfLength + shape.bodyRadius) + 3
        let wall = DynamicBodyScene.box(center: SIMD3(face - 50, 0, 40), half: SIMD3(50, 200, 40))
        func push(_ move: SIMD2<Float>) -> LongBodyPush {
            shape.largestPush(
                pose: (.zero, 0), displacement: move, ground: { _ in 0 },
                query: DynamicBodyScene.candidateQuery([wall])
            )
        }
        let away = push(SIMD2(5, 0))
        #expect(simd_length(away.added) < 0.01, "push \(away)")
        let into = push(SIMD2(-5, 0))
        #expect(into.added.x > 4.9 && into.part == .body(0), "push \(into)")
        #expect(abs(into.resting.x - 3) < 0.1)
    }

    /// A step searches the world for shapes once for the whole body, and reads the ground
    /// twice per end: where it stands and where it goes.
    @Test
    func aStepSearchesOnceForAllItsParts() throws {
        let shape = try #require(LongBodyShape(halfExtents: Self.horse))
        let wall = DynamicBodyScene.box(center: SIMD3(300, 0, 40), half: SIMD3(50, 200, 40))
        var searches = 0
        var grounds = 0
        _ = shape.largestPush(
            pose: (.zero, 0), displacement: SIMD2(5, 0),
            ground: { _ in
                grounds += 1
                return 0
            },
            query: { bounds in
                searches += 1
                return DynamicBodyScene.candidateQuery([wall])(bounds)
            }
        )
        #expect(searches == 1)
        #expect(grounds == 4)
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
