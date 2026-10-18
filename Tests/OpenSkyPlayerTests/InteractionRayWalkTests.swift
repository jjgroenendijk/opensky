// The tree walk must pick the hit the bounding-box query picked: the same shape,
// the same distance, and the same tie-break, over seeded random scenes.

@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsMesh
@testable import OpenSkyPhysics
@testable import OpenSkyPlayer
@testable import OpenSkyWorldInterface
import simd
import Testing

struct InteractionRayWalkTests {
    /// A small fixed generator, so every run tests the same scenes.
    private struct Seeded {
        var state: UInt64

        mutating func unit() -> Float {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(state >> 40) / Float(1 << 24)
        }

        mutating func point(spread: Float) -> SIMD3<Float> {
            SIMD3(unit(), unit(), unit()) * spread * 2 - spread
        }
    }

    private static func sphere(_ reference: UInt32, at center: SIMD3<Float>, radius: Float)
        -> StaticCollisionShape
    {
        StaticCollisionShape(
            reference: FormID(reference),
            transform: float4x4(columns: (
                SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(center, 1)
            )),
            geometry: .sphere(radius: radius),
            bounds: ModelBounds(min: center - radius, max: center + radius)
        )
    }

    private static func set(_ shapes: [StaticCollisionShape]) -> StaticCollisionSet {
        StaticCollisionSet(location: nil, shapes: shapes, stats: StaticCollisionStats())
    }

    private static func scene(seed: UInt64)
        -> (sets: [StaticCollisionSet], loose: [StaticCollisionShape])
    {
        var random = Seeded(state: seed)
        var reference: UInt32 = 0
        func shapes(_ count: Int) -> [StaticCollisionShape] {
            (0 ..< count).map { _ in
                reference += 1
                return sphere(
                    reference,
                    at: random.point(spread: 400),
                    radius: 4 + random.unit() * 30
                )
            }
        }
        return ([set(shapes(60)), set(shapes(25))], shapes(3))
    }

    @Test(arguments: [UInt64(1), 2, 3, 4])
    func walkFindsTheHitTheBoxQueryFinds(seed: UInt64) throws {
        let scene = Self.scene(seed: seed)
        var random = Seeded(state: seed &+ 99)
        for _ in 0 ..< 200 {
            let ray = try #require(InteractionRay(
                origin: random.point(spread: 450),
                direction: random.point(spread: 1) + SIMD3(0.001, 0, 0),
                maximumDistance: 50 + random.unit() * 900
            ))
            let boxed = scene.sets.flatMap { $0.candidates(overlapping: ray.bounds) } + scene.loose
            let expected = InteractionRaycaster.nearestHit(ray: ray, shapes: boxed)
            let walked = InteractionRaycaster.nearestHit(
                ray: ray, sets: scene.sets, shapes: scene.loose
            )
            #expect(walked == expected)
            #expect(
                InteractionRaycaster.hasHit(ray: ray, sets: scene.sets, shapes: scene.loose)
                    == (expected != nil)
            )
        }
    }

    @Test func equalDistancesBreakTiesByReferenceAsBefore() throws {
        let near = Self.set([
            Self.sphere(9, at: SIMD3(20, 0, 0), radius: 5),
            Self.sphere(4, at: SIMD3(20, 0, 0), radius: 5)
        ])
        let ray = try #require(InteractionRay(origin: .zero, direction: SIMD3(1, 0, 0)))
        let hit = InteractionRaycaster.nearestHit(ray: ray, sets: [near], shapes: [])
        #expect(hit?.reference == FormID(4))
        #expect(abs((hit?.distance ?? 0) - 15) < 0.001)
    }

    @Test func aRayOutsideEveryBoxHitsNothing() throws {
        let scene = Self.set([Self.sphere(1, at: SIMD3(0, 50, 0), radius: 5)])
        let ray = try #require(InteractionRay(origin: .zero, direction: SIMD3(1, 0, 0)))
        #expect(InteractionRaycaster.nearestHit(ray: ray, sets: [scene], shapes: []) == nil)
        #expect(!InteractionRaycaster.hasHit(ray: ray, sets: [scene], shapes: []))
    }
}
