// The faces built for a bhkConvexVerticesShape from its points and planes
// (docs/formats/nif-collision.md). Synthetic hulls only.

@testable import OpenSkyFormatsMesh
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct NIFCollisionConvexHullTests {
    /// A door leaf: 92 wide, 2 thick, 168 tall, in engine units.
    private static let slab: [SIMD3<Float>] = [
        SIMD3(0, 0, 0), SIMD3(92, 0, 0), SIMD3(0, 2, 0), SIMD3(92, 2, 0),
        SIMD3(0, 0, 168), SIMD3(92, 0, 168), SIMD3(0, 2, 168), SIMD3(92, 2, 168)
    ]

    /// The slab's six planes, `n·x + w = 0`, moved out by `radius`.
    private static func planes(radius: Float) -> [SIMD4<Float>] {
        [
            SIMD4(-1, 0, 0, 0 - radius), SIMD4(1, 0, 0, -92 - radius),
            SIMD4(0, -1, 0, 0 - radius), SIMD4(0, 1, 0, -2 - radius),
            SIMD4(0, 0, -1, 0 - radius), SIMD4(0, 0, 1, -168 - radius)
        ]
    }

    @Test func planesOnThePointsGiveEveryFace() {
        let indices = NIFCollisionConvexHull.indices(
            vertices: Self.slab,
            planes: Self.planes(radius: 0)
        )
        #expect(indices.count == 12 * 3)
    }

    /// Some vanilla door leaves store planes 0.05 Havok units outside their points, the
    /// shape's convex radius. Without faces, a view ray and a walking player pass through.
    @Test func planesMovedOutByTheConvexRadiusStillGiveEveryFace() {
        let radius = 0.05 * NIFCollisionModel.havokToEngineScale
        let indices = NIFCollisionConvexHull.indices(
            vertices: Self.slab, planes: Self.planes(radius: radius)
        )
        #expect(indices.count == 12 * 3)
        let faces = Set(stride(from: 0, to: indices.count, by: 3).map { offset in
            let triangle = indices[offset ..< offset + 3].map { Self.slab[Int($0)] }
            return simd_normalize(simd_cross(triangle[1] - triangle[0], triangle[2] - triangle[0]))
        })
        #expect(faces.count == 6)
    }
}
