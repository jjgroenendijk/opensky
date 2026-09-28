// Terrain walk sampling over synthetic heights only. Topology must match
// TerrainMeshBuilder's SW->NE rendered triangles, never a bilinear patch.

@testable import opensky
import simd
import Testing

struct TerrainHeightFieldTests {
    @Test
    func flatFieldReturnsHeightAndUpNormal() throws {
        let field = try #require(Self.field(height: 42))
        let sample = try #require(field.sample(at: SIMD2(1024, 2048)))
        #expect(abs(sample.height - 42) < 1e-6)
        #expect(simd_distance(sample.normal, SIMD3<Float>(0, 0, 1)) < 1e-6)
    }

    @Test
    func saddleQuadUsesRenderedTrianglePlanesNotBilinearPatch() throws {
        var heights = Self.heights(0)
        // First quad: SW/NE = 0, SE/NW = 100. At center, rendered diagonal
        // lies on height 0; bilinear interpolation would return 50.
        heights[0] = 0
        heights[1] = 100
        heights[TerrainMeshBuilder.gridDimension] = 100
        heights[TerrainMeshBuilder.gridDimension + 1] = 0
        let field = try #require(TerrainHeightField(
            coordinate: CellCoordinate(x: 0, y: 0),
            heights: heights
        ))

        let diagonal = try #require(field.sample(at: SIMD2(64, 64)))
        #expect(abs(diagonal.height) < 1e-5)
        #expect(abs(diagonal.height - 50) > 49)

        let south = try #require(field.sample(at: SIMD2(96, 32)))
        let north = try #require(field.sample(at: SIMD2(32, 96)))
        #expect(abs(south.height - 50) < 1e-5)
        #expect(abs(north.height - 50) < 1e-5)
        #expect(south.normal != north.normal)
        #expect(south.normal.z > 0)
        #expect(north.normal.z > 0)
    }

    @Test
    func hiddenQuadrantHasNoGround() throws {
        let field = try #require(TerrainHeightField(
            coordinate: CellCoordinate(x: 0, y: 0),
            heights: Self.heights(0),
            hiddenQuadrants: 1 << 3
        ))
        #expect(field.sample(at: SIMD2(3000, 3000)) == nil)
        #expect(field.sample(at: SIMD2(1000, 1000)) != nil)
    }

    @Test
    func negativeCellUsesWorldOrigin() throws {
        let field = try #require(Self.field(
            coordinate: CellCoordinate(x: -2, y: -1),
            height: -300
        ))
        let origin = SIMD2<Float>(-2 * 4096, -1 * 4096)
        #expect(field.sample(at: origin + SIMD2(64, 64))?.height == -300)
        #expect(field.sample(at: SIMD2(64, 64)) == nil)
    }

    @Test
    func compositionHandsExactBorderToEastNeighbor() throws {
        var composition = CellSceneComposition()
        try composition.setCell(
            Self.cell(field: #require(Self.field(
                coordinate: CellCoordinate(x: 0, y: 0), height: 10
            ))),
            at: CellCoordinate(x: 0, y: 0)
        )
        try composition.setCell(
            Self.cell(field: #require(Self.field(
                coordinate: CellCoordinate(x: 1, y: 0), height: 20
            ))),
            at: CellCoordinate(x: 1, y: 0)
        )

        #expect(composition.sampleTerrain(at: SIMD2(4095.5, 1000))?.height == 10)
        #expect(composition.sampleTerrain(at: SIMD2(4096, 1000))?.height == 20)
    }

    static func heights(_ value: Float) -> [Float] {
        [Float](repeating: value, count: Land.vertexCount)
    }

    static func field(
        coordinate: CellCoordinate = CellCoordinate(x: 0, y: 0),
        height: Float
    ) -> TerrainHeightField? {
        TerrainHeightField(coordinate: coordinate, heights: heights(height))
    }

    static func cell(field: TerrainHeightField) -> CellScene {
        CellScene(
            renderScene: RenderScene(instances: []),
            summary: CellLoadSummary(
                cellName: "terrain-test",
                gridX: field.coordinate.x,
                gridY: field.coordinate.y,
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
            location: .exterior(field.coordinate),
            terrainHeightField: field
        )
    }
}
