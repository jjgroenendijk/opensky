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
}
