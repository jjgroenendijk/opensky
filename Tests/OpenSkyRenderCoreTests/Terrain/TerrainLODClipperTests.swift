@testable import OpenSkyFormatsCore
@testable import OpenSkyRenderCore
import simd
import Testing

struct TerrainLODClipperTests {
    private func sourceModel() -> Model {
        let mesh = Mesh(
            name: "crossing",
            transform: matrix_identity_float4x4,
            positions: [SIMD3(0, 0, 2), SIMD3(8192, 0, 4), SIMD3(0, 8192, 6)],
            normals: [SIMD3(0, 0, 1), SIMD3(0, 0, 1), SIMD3(0, 0, 1)],
            tangents: [],
            bitangents: [],
            uvs: [SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1)],
            colors: [],
            indices: [0, 1, 2],
            materialSlot: 0
        )
        return Model(meshes: [mesh], materials: [.fallback], skippedShapeCount: 0)
    }

    @Test func clipsCrossingTriangleToExactVisibleCellRectangle() {
        let mask = TerrainLODClipMask(
            level: 2,
            blockOrigin: CellCoordinate(x: 0, y: 0),
            visibleCells: [CellCoordinate(x: 0, y: 0)]
        )
        let clipped = TerrainLODClipper.clipped(sourceModel(), to: mask)

        #expect(!clipped.meshes.isEmpty)
        #expect(clipped.meshes.allSatisfy { $0.normals.count == $0.positions.count })
        #expect(clipped.meshes.allSatisfy { $0.uvs.count == $0.positions.count })
        for position in clipped.meshes.flatMap(\.positions) {
            #expect(position.x >= 0 && position.x <= TerrainMeshBuilder.cellSize)
            #expect(position.y >= 0 && position.y <= TerrainMeshBuilder.cellSize)
        }
        #expect(abs(area(of: clipped) - 4096 * 4096) < 1)
    }

    @Test func adjacentMasksPartitionTriangleWithoutOverlapOrGap() {
        let origin = CellCoordinate(x: 0, y: 0)
        let masks = [
            TerrainLODClipMask(
                level: 2,
                blockOrigin: origin,
                visibleCells: [CellCoordinate(x: 0, y: 0)]
            ),
            TerrainLODClipMask(
                level: 2,
                blockOrigin: origin,
                visibleCells: [
                    CellCoordinate(x: 1, y: 0),
                    CellCoordinate(x: 0, y: 1)
                ]
            )
        ]
        let total = masks.reduce(Float.zero) {
            $0 + area(of: TerrainLODClipper.clipped(sourceModel(), to: $1))
        }
        #expect(abs(total - 8192 * 8192 / 2) < 1)
    }

    /// Level 2 owns cell (0, 0); the coarser neighbour beyond x = 4096 has other edge
    /// heights. The cut edge hangs a skirt deep enough to close the step between them.
    @Test func aCutEdgeHangsASkirtThatClosesTheStepToANeighbour() {
        let mask = TerrainLODClipMask(
            level: 2, blockOrigin: CellCoordinate(x: 0, y: 0),
            visibleCells: [CellCoordinate(x: 0, y: 0)]
        )
        let clipped = TerrainLODClipper.clipped(sourceModel(), to: mask)
        let cut = TerrainMeshBuilder.cellSize
        let onCut = clipped.meshes.flatMap(\.positions).filter { abs($0.x - cut) < 0.01 }
        let top = onCut.map(\.z).max() ?? 0
        let bottom = onCut.map(\.z).min() ?? 0
        #expect(top - bottom >= TerrainLODClipper.skirtDepth(level: 2) - 1)
        #expect(TerrainLODClipper.skirtDepth(level: 4) == 1000)
        #expect(TerrainLODClipper.skirtDepth(level: 32) == 4000)

        let inner = clipped.meshes.flatMap(\.positions)
            .filter { abs($0.x) < 0.01 && $0.y > 1 && $0.y < cut - 1 }
        #expect(inner.allSatisfy { $0.z >= 0 }, "the block's own outer edge gets no new skirt")
    }

    @Test func aVanillaSkirtOnAKeptCellLineSurvivesTheClip() {
        let skirt = Mesh(
            name: "skirt", transform: matrix_identity_float4x4,
            positions: [SIMD3(0, 100, 10), SIMD3(0, 200, 10), SIMD3(0, 100, -990)],
            normals: [], tangents: [], bitangents: [], uvs: [], colors: [],
            indices: [0, 1, 2], materialSlot: 0
        )
        let model = Model(meshes: [skirt], materials: [.fallback], skippedShapeCount: 0)
        let mask = TerrainLODClipMask(
            level: 2, blockOrigin: CellCoordinate(x: 0, y: 0),
            visibleCells: [CellCoordinate(x: 0, y: 0)]
        )
        #expect(!TerrainLODClipper.clipped(model, to: mask).meshes.isEmpty)
    }

    private func area(of model: Model) -> Float {
        model.meshes.reduce(0) { sum, mesh in
            sum + stride(from: 0, to: mesh.indices.count, by: 3).reduce(0) { area, offset in
                let first = mesh.positions[Int(mesh.indices[offset])]
                let second = mesh.positions[Int(mesh.indices[offset + 1])]
                let third = mesh.positions[Int(mesh.indices[offset + 2])]
                let twiceArea = abs(
                    (second.x - first.x) * (third.y - first.y)
                        - (second.y - first.y) * (third.x - first.x)
                )
                return area + twiceArea / 2
            }
        }
    }
}
