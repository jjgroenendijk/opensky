// CPU-side terrain collision surface for walk mode (milestone 4.1). LAND's
// 33x33 heights use the exact SW->NE quad split emitted by
// TerrainMeshBuilder, so sampled height + face normal match rendered planes.

import simd

/// One point on rendered terrain in world space.
nonisolated struct TerrainGroundSample: Equatable {
    let height: Float
    let normal: SIMD3<Float>
    /// The MATT material of the ground here (issue #358), from the landscape
    /// texture painted heaviest at the nearest terrain vertex. Nil where the
    /// cell carries no resolved material — a LAND-less fallback plane, or a
    /// texture whose LTEX names no MATT.
    let material: FormID?

    init(height: Float, normal: SIMD3<Float>, material: FormID? = nil) {
        self.height = height
        self.normal = normal
        self.material = material
    }
}

/// Immutable height field retained beside one streamed exterior CellScene.
/// Cell load/unload therefore controls render + collision lifetime together.
nonisolated struct TerrainHeightField: Equatable {
    let coordinate: CellCoordinate
    let heights: [Float]
    let hiddenQuadrants: UInt32
    /// Per-vertex ground material, or nil when the cell resolved none.
    let surfaceMaterials: TerrainSurfaceMaterials?

    init?(
        coordinate: CellCoordinate,
        heights: [Float],
        hiddenQuadrants: UInt32 = 0,
        surfaceMaterials: TerrainSurfaceMaterials? = nil
    ) {
        guard heights.count == Land.vertexCount else { return nil }
        self.coordinate = coordinate
        self.heights = heights
        self.hiddenQuadrants = hiddenQuadrants
        self.surfaceMaterials = surfaceMaterials
    }

    /// Samples a world XY point. Each 128-unit quad is split SW->NE exactly
    /// like TerrainMeshBuilder.gridMesh: south triangle SW/SE/NE, north
    /// triangle SW/NE/NW. Barycentric interpolation stays on those planes;
    /// it is intentionally not bilinear.
    func sample(at worldPosition: SIMD2<Float>) -> TerrainGroundSample? {
        let origin = SIMD2<Float>(
            Float(coordinate.x) * TerrainMeshBuilder.cellSize,
            Float(coordinate.y) * TerrainMeshBuilder.cellSize
        )
        let local = worldPosition - origin
        guard
            local.x >= 0, local.y >= 0,
            local.x <= TerrainMeshBuilder.cellSize,
            local.y <= TerrainMeshBuilder.cellSize
        else { return nil }

        let gridMaximum = TerrainMeshBuilder.gridDimension - 2
        let scaledX = local.x / TerrainMeshBuilder.quadSize
        let scaledY = local.y / TerrainMeshBuilder.quadSize
        let column = min(Int(scaledX.rounded(.down)), gridMaximum)
        let row = min(Int(scaledY.rounded(.down)), gridMaximum)
        guard !isHidden(column: column, row: row) else { return nil }

        let fractionX = min(max(scaledX - Float(column), 0), 1)
        let fractionY = min(max(scaledY - Float(row), 0), 1)
        let southWest = height(column: column, row: row)
        let southEast = height(column: column + 1, row: row)
        let northWest = height(column: column, row: row + 1)
        let northEast = height(column: column + 1, row: row + 1)

        // The material is per vertex while the height is interpolated across
        // the face, so it snaps to the nearest corner of the quad rather than
        // blending: a surface is one material or the other, never half of each.
        let material = surfaceMaterials?.material(
            column: column + (fractionX >= 0.5 ? 1 : 0),
            row: row + (fractionY >= 0.5 ? 1 : 0)
        )
        if fractionY <= fractionX {
            let height = southWest * (1 - fractionX)
                + southEast * (fractionX - fractionY)
                + northEast * fractionY
            return TerrainGroundSample(
                height: height,
                normal: faceNormal(
                    southWest: southWest,
                    eastOrNorthEast: southEast,
                    northOrNorthEast: northEast,
                    secondAxisIsNorth: false
                ),
                material: material
            )
        }
        let height = southWest * (1 - fractionY)
            + northEast * fractionX
            + northWest * (fractionY - fractionX)
        return TerrainGroundSample(
            height: height,
            normal: faceNormal(
                southWest: southWest,
                eastOrNorthEast: northEast,
                northOrNorthEast: northWest,
                secondAxisIsNorth: true
            ),
            material: material
        )
    }

    private func height(column: Int, row: Int) -> Float {
        heights[row * TerrainMeshBuilder.gridDimension + column]
    }

    private func isHidden(column: Int, row: Int) -> Bool {
        let east = column >= (TerrainMeshBuilder.gridDimension - 1) / 2
        let north = row >= (TerrainMeshBuilder.gridDimension - 1) / 2
        let quadrant = (north ? 2 : 0) + (east ? 1 : 0)
        return hiddenQuadrants & (1 << UInt32(quadrant)) != 0
    }

    /// Normal from same CCW vertex order as rendered indices. Parameters are
    /// named around triangle role to keep both triangle branches explicit.
    private func faceNormal(
        southWest: Float,
        eastOrNorthEast: Float,
        northOrNorthEast: Float,
        secondAxisIsNorth: Bool
    ) -> SIMD3<Float> {
        let size = TerrainMeshBuilder.quadSize
        let first = secondAxisIsNorth
            ? SIMD3<Float>(size, size, eastOrNorthEast - southWest)
            : SIMD3<Float>(size, 0, eastOrNorthEast - southWest)
        let second = secondAxisIsNorth
            ? SIMD3<Float>(0, size, northOrNorthEast - southWest)
            : SIMD3<Float>(size, size, northOrNorthEast - southWest)
        return simd_normalize(simd_cross(first, second))
    }
}
