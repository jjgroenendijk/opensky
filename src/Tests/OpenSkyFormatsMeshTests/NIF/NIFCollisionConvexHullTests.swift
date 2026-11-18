// The faces built for a bhkConvexVerticesShape from its points and planes
// (docs/formats/nif-collision.md). Synthetic hulls only.

import Foundation
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
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

    @Test func growingMovesEveryFaceOutByTheRadius() {
        let grown = NIFCollisionConvexHull.grown(
            vertices: Self.slab, planes: Self.planes(radius: 0), radius: 3.5
        )
        #expect(grown.indices.count == 12 * 3)
        let low = grown.vertices.reduce(SIMD3<Float>(repeating: .infinity)) { simd_min($0, $1) }
        let high = grown.vertices.reduce(SIMD3<Float>(repeating: -.infinity)) { simd_max($0, $1) }
        #expect(simd_distance(low, SIMD3(-3.5, -3.5, -3.5)) < 1e-3)
        #expect(simd_distance(high, SIMD3(95.5, 5.5, 171.5)) < 1e-3)
    }

    @Test func noRadiusKeepsThePoints() {
        let grown = NIFCollisionConvexHull.grown(
            vertices: Self.slab, planes: Self.planes(radius: 0), radius: 0
        )
        #expect(grown.vertices == Self.slab)
        #expect(grown.indices.count == 12 * 3)
    }

    @Test func decodedShapesGrowByTheirConvexRadius() throws {
        let scale = NIFCollisionModel.havokToEngineScale
        let file = try NIFFile(data: NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(prefix: NIFFixture.avObjectPrefix(collisionRef: 1))),
            .init("bhkCollisionObject", NIFCollisionFixture.collisionObject(body: 2)),
            .init("bhkRigidBody", NIFCollisionFixture.rigidBody(shape: 3)),
            .init("bhkListShape", NIFCollisionFixture.list([4, 5, 6])),
            .init("bhkConvexVerticesShape", NIFCollisionFixture.convexVertices(
                [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)],
                normals: [
                    SIMD4(-1, 0, 0, -0.1), SIMD4(0, -1, 0, -0.1), SIMD4(0, 0, -1, -0.1),
                    SIMD4(1, 1, 1, -1) / sqrtf(3) - SIMD4(0, 0, 0, 0.1)
                ],
                radius: 0.1
            )),
            .init("bhkBoxShape", NIFCollisionFixture.box(SIMD3(1, 2, 3), radius: 0.1)),
            .init("bhkCylinderShape", NIFBlockFixture.cylinder(
                first: SIMD3(0, 0, -1), second: SIMD3(0, 0, 1), radius: 0.5, shell: 0.1
            ))
        ]))
        let shapes = try #require(file.collisionModel().bodies.first).shapes
        try #require(shapes.count == 3)
        guard case let .convexVertices(vertices, hull) = shapes[0].geometry else {
            Issue.record("expected convex vertices, got \(shapes[0].geometry)")
            return
        }
        #expect(hull.count == 12)
        let low = vertices.reduce(SIMD3<Float>(repeating: .infinity)) { simd_min($0, $1) }
        #expect(simd_distance(low, SIMD3(repeating: -0.1 * scale)) < 1e-2)
        guard case let .box(halfExtents) = shapes[1].geometry else {
            Issue.record("expected a box, got \(shapes[1].geometry)")
            return
        }
        #expect(simd_distance(halfExtents, SIMD3(1.1, 2.1, 3.1) * scale) < 1e-2)
        guard case let .convexVertices(prism, _) = shapes[2].geometry else {
            Issue.record("expected a prism, got \(shapes[2].geometry)")
            return
        }
        let top = prism.map(\.z).max() ?? 0
        #expect(abs(top - 1.1 * scale) < 1e-2)
        #expect(prism.allSatisfy { abs(simd_length(SIMD2($0.x, $0.y)) - 0.6 * scale) < 1e-2 })
    }
}
