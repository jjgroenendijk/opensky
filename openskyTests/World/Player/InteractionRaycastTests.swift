// Finite interaction raycast over synthetic engine collision values only.

@testable import opensky
import simd
import Testing

struct InteractionRaycastTests {
    private func ray(
        origin: SIMD3<Float> = .zero,
        direction: SIMD3<Float> = SIMD3(1, 0, 0),
        maximumDistance: Float = 192
    ) throws -> InteractionRay {
        try #require(InteractionRay(
            origin: origin,
            direction: direction,
            maximumDistance: maximumDistance
        ))
    }

    private func shape(
        reference: UInt32,
        transform: float4x4 = matrix_identity_float4x4,
        geometry: NIFCollisionGeometry
    ) -> StaticCollisionShape {
        StaticCollisionShape(
            reference: FormID(reference),
            transform: transform,
            geometry: geometry,
            bounds: ModelBounds(
                min: SIMD3(repeating: -10000),
                max: SIMD3(repeating: 10000)
            )
        )
    }

    @Test func hitsTriangleSoupAndConvexFaces() throws {
        let vertices = [
            SIMD3<Float>(5, -1, -1),
            SIMD3<Float>(5, 1, -1),
            SIMD3<Float>(5, 0, 1)
        ]
        for geometry in [
            NIFCollisionGeometry.triangleSoup(vertices: vertices, indices: [0, 1, 2]),
            .convexVertices(vertices: vertices, hullIndices: [0, 1, 2])
        ] {
            let hit = try InteractionRaycaster.nearestHit(
                ray: ray(),
                shapes: [shape(reference: 7, geometry: geometry)]
            )
            #expect(hit?.reference == FormID(7))
            #expect(abs((hit?.distance ?? 0) - 5) < 0.0001)
        }
    }

    @Test func hitsBoxSphereAndCapsule() throws {
        let cases: [(geometry: NIFCollisionGeometry, expected: Float)] = [
            (.box(halfExtents: SIMD3(repeating: 1)), 4),
            (.sphere(radius: 1), 4),
            (.capsule(
                first: SIMD3(0, -1, 0),
                second: SIMD3(0, 1, 0),
                radius: 1
            ), 4)
        ]
        for entry in cases {
            let hit = try InteractionRaycaster.nearestHit(
                ray: ray(),
                shapes: [
                    shape(
                        reference: 8,
                        transform: MatrixMath.translation(SIMD3(5, 0, 0)),
                        geometry: entry.geometry
                    )
                ]
            )
            #expect(abs((hit?.distance ?? 0) - entry.expected) < 0.0001)
        }
    }

    @Test func transformedDirectionKeepsWorldDistance() throws {
        let nonuniformScale = float4x4(
            diagonal: SIMD4<Float>(2, 3, 4, 1)
        )
        let transform = MatrixMath.translation(SIMD3(10, 0, 0))
            * MatrixMath.rotationX(radians: 0.4)
            * nonuniformScale
        let hit = try InteractionRaycaster.nearestHit(
            ray: ray(),
            shapes: [shape(
                reference: 9,
                transform: transform,
                geometry: .sphere(radius: 1)
            )]
        )
        #expect(abs((hit?.distance ?? 0) - 8) < 0.0001)
    }

    @Test func nearestHitAndEqualDistanceTieAreDeterministic() throws {
        let far = shape(
            reference: 1,
            transform: MatrixMath.translation(SIMD3(12, 0, 0)),
            geometry: .sphere(radius: 1)
        )
        let tiedHigh = shape(
            reference: 9,
            transform: MatrixMath.translation(SIMD3(5, 0, 0)),
            geometry: .sphere(radius: 1)
        )
        let tiedLow = shape(
            reference: 3,
            transform: MatrixMath.translation(SIMD3(5, 0, 0)),
            geometry: .sphere(radius: 1)
        )
        let hit = try InteractionRaycaster.nearestHit(
            ray: ray(),
            shapes: [far, tiedHigh, tiedLow]
        )
        #expect(hit?.reference == FormID(3))
        #expect(abs((hit?.distance ?? 0) - 4) < 0.0001)
    }

    @Test func rejectsBehindOutOfRangeAndMalformedShapes() throws {
        let shapes = [
            shape(
                reference: 1,
                transform: MatrixMath.translation(SIMD3(-5, 0, 0)),
                geometry: .sphere(radius: 1)
            ),
            shape(
                reference: 2,
                transform: MatrixMath.translation(SIMD3(20, 0, 0)),
                geometry: .sphere(radius: 1)
            ),
            shape(
                reference: 3,
                geometry: .triangleSoup(vertices: [.zero], indices: [0, 1, 2])
            ),
            shape(reference: 4, geometry: .sphere(radius: 0))
        ]
        #expect(try InteractionRaycaster.nearestHit(
            ray: ray(maximumDistance: 10),
            shapes: shapes
        ) == nil)
    }

    @Test func originInsidePrimitiveReturnsForwardExit() throws {
        for geometry in [
            NIFCollisionGeometry.box(halfExtents: SIMD3(repeating: 2)),
            .sphere(radius: 2),
            .capsule(first: SIMD3(0, -1, 0), second: SIMD3(0, 1, 0), radius: 2)
        ] {
            let hit = try InteractionRaycaster.nearestHit(
                ray: ray(),
                shapes: [shape(reference: 5, geometry: geometry)]
            )
            #expect(abs((hit?.distance ?? 0) - 2) < 0.0001)
        }
    }

    @Test func invalidRaysAndSingularTransformsDoNotHit() throws {
        #expect(InteractionRay(origin: .zero, direction: .zero) == nil)
        #expect(InteractionRay(
            origin: .zero,
            direction: SIMD3(1, 0, 0),
            maximumDistance: 0
        ) == nil)
        let singular = float4x4(diagonal: SIMD4<Float>(0, 1, 1, 1))
        let hit = try InteractionRaycaster.nearestHit(
            ray: ray(),
            shapes: [shape(
                reference: 6,
                transform: singular,
                geometry: .sphere(radius: 1)
            )]
        )
        #expect(hit == nil)
    }
}
