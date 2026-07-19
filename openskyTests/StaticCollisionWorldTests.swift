// Per-cell static collision BVH + composition lifecycle over synthetic engine
// values only. No game content, file parsing, or Metal device required.

@testable import opensky
import simd
import Testing

struct StaticCollisionWorldTests {
    private func shape(reference: UInt32, center: SIMD3<Float>) -> StaticCollisionShape {
        let extent = SIMD3<Float>(repeating: 1)
        return StaticCollisionShape(
            reference: FormID(reference),
            transform: MatrixMath.translation(center),
            geometry: .sphere(radius: 1),
            bounds: ModelBounds(min: center - extent, max: center + extent)
        )
    }

    private func collisionSet(
        coordinate: CellCoordinate,
        shapes: [StaticCollisionShape]
    ) -> StaticCollisionSet {
        var stats = StaticCollisionStats()
        stats.shapeCount = shapes.count
        return StaticCollisionSet(
            location: .exterior(coordinate),
            shapes: shapes,
            stats: stats,
            buildDurationMS: 3.5
        )
    }

    private func scene(_ collision: StaticCollisionSet) -> CellScene {
        CellScene(
            renderScene: RenderScene(instances: []),
            summary: CellLoadSummary(
                cellName: "collision-test",
                gridX: 0,
                gridY: 0,
                totalRefCount: 0,
                drawnRefCount: 0,
                unsupportedBaseSkipCount: 0,
                markerSkipCount: 0,
                modelFailureSkipCount: 0,
                malformedRefSkipCount: 0,
                modelCount: 0,
                textureCount: 0,
                missingTextureCount: 0
            ),
            bounds: nil,
            staticCollision: collision
        )
    }

    @Test func bvhReturnsOnlyOverlappingShapesInStableOrder() {
        let coordinate = CellCoordinate(x: 0, y: 0)
        let shapes = (0 ..< 8).map {
            shape(reference: UInt32($0 + 1), center: SIMD3(Float($0) * 10, 0, 0))
        }
        let collision = collisionSet(coordinate: coordinate, shapes: shapes)
        #expect(collision.indexNodeCount > 1)
        let candidates = collision.candidates(overlapping: ModelBounds(
            min: SIMD3(19, -2, -2),
            max: SIMD3(31, 2, 2)
        ))
        #expect(candidates.map(\.reference) == [FormID(3), FormID(4)])
    }

    @Test func cellRemovalEvictsCollisionShapesAndIndexTogether() {
        let coordinate = CellCoordinate(x: 6, y: -2)
        let collision = collisionSet(
            coordinate: coordinate,
            shapes: [shape(reference: 1, center: SIMD3(25000, -8000, 100))]
        )
        var composition = CellSceneComposition()
        composition.setCell(scene(collision), at: coordinate)
        #expect(composition.collisionStats().shapeCount == 1)
        #expect(composition.collisionCandidates(overlapping: collision.shapes[0].bounds).count == 1)

        let removed = composition.removeCell(at: coordinate)
        #expect(removed?.staticCollision.stats.shapeCount == 1)
        #expect(composition.collisionStats().shapeCount == 0)
        #expect(composition.collisionCandidates(overlapping: collision.shapes[0].bounds).isEmpty)
    }

    @Test func largeTriangleSoupPartitionsBroadphaseWithoutChangingTriangles() {
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []
        for triangle in 0 ..< 1200 {
            let x: Float = triangle < 600 ? 0 : 2048
            let base = UInt32(vertices.count)
            vertices.append(contentsOf: [
                SIMD3(x, Float(triangle % 10), 0),
                SIMD3(x + 8, Float(triangle % 10), 0),
                SIMD3(x, Float(triangle % 10) + 8, 0)
            ])
            indices.append(contentsOf: [base, base + 1, base + 2])
        }
        let leaves = StaticCollisionShape.placed(
            reference: FormID(7),
            transform: matrix_identity_float4x4,
            geometry: .triangleSoup(vertices: vertices, indices: indices)
        )
        #expect(leaves.count > 1)
        #expect(leaves.reduce(0) { $0 + $1.triangleCount } == 1200)

        let collision = collisionSet(coordinate: coordinate(0, 0), shapes: leaves)
        let nearby = collision.candidates(overlapping: ModelBounds(
            min: SIMD3(-16, -16, -16),
            max: SIMD3(32, 32, 16)
        ))
        let nearbyTriangleCount = nearby.reduce(0) { $0 + $1.triangleCount }
        #expect(nearbyTriangleCount == 640)
        #expect(nearbyTriangleCount < 1200)
    }

    private func coordinate(_ x: Int32, _ y: Int32) -> CellCoordinate {
        CellCoordinate(x: x, y: y)
    }
}
