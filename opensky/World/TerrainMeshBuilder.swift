// Build engine Mesh/Model values from a decoded LAND record (todo 3.1 terrain).
// Pure geometry: takes the decoded height field / normals / colors plus a
// per-quadrant resolved Material and emits one sub-mesh per painted quadrant so
// the existing single-texture static pipeline draws terrain today. Splat
// blending (ATXT/VTXT layers) is the next commit — this stage draws each
// quadrant's BTXT base texture only.
//
// Authoring conventions (docs/decisions/coordinates.md): Skyrim Z-up world at
// native units, +X east, +Y north, +Z up. Triangles wind counter-clockwise
// seen from above (+Z) — the pipeline's front-face winding, matching the demo
// ground plane. Layout + placement math: docs/engine/terrain.md.

import Foundation
import simd

nonisolated enum TerrainMeshBuilder {
    /// One exterior cell spans 4096 game units per edge (docs/decisions/
    /// coordinates.md), 32 quads at 128 units each -> a 33x33 vertex grid.
    static let cellSize: Float = 4096
    static let quadSize: Float = 128
    /// 33x33 vertices, matching Land.dimension.
    static let gridDimension = Land.dimension
    /// Each cell splits into four 17x17 quadrants sharing the center row/col
    /// (col/row 16). Quadrant q owns cols/rows [origin, origin+16].
    static let quadrantDimension = 17

    /// UV density: grid position in quads scaled by this reciprocal, so one
    /// texture repeat spans `uvQuadsPerRepeat` quads. The exact vanilla tiling
    /// density is UNCONFIRMED (community lore varies) — this constant is a
    /// verifiable starting point, tuned visually when the splat pipeline lands.
    static let uvQuadsPerRepeat: Float = 2

    /// Builds a terrain Model from a decoded LAND. One sub-mesh per emitted
    /// quadrant, each carrying the Material `materialForQuadrant` resolves for
    /// its BTXT base texture. Quadrants whose force-hide bit is set in
    /// `hiddenQuadrants` are skipped (XCLC land-quad flags, UESP CELL) and so
    /// are quadrants with no height data.
    ///
    /// - Parameters:
    ///   - hiddenQuadrants: XCLC quad-flags; bit `1 << q` hides quadrant q.
    ///   - materialForQuadrant: quadrant index (0-3) -> resolved base Material.
    static func model(
        land: Land,
        hiddenQuadrants: UInt32,
        materialForQuadrant: (UInt8) -> Material
    ) -> Model {
        guard let heights = land.heightField?.heights, heights.count == Land.vertexCount else {
            return Model(meshes: [], materials: [], skippedShapeCount: 0)
        }
        let field = Field(heights: heights, normals: land.normals, colors: land.colors)
        var meshes: [Mesh] = []
        var materials: [Material] = []
        for quadrant in UInt8(0) ... 3 {
            // UESP CELL XCLC: bits 0x1-0x8 force-hide the matching land quad.
            guard hiddenQuadrants & (1 << UInt32(quadrant)) == 0 else { continue }
            let slot = materials.count
            materials.append(materialForQuadrant(quadrant))
            meshes.append(gridMesh(
                name: "terrain-quadrant-\(quadrant)",
                patch: quadrantPatch(quadrant),
                materialSlot: slot
            ) { col, row in vertex(field: field, col: col, row: row) })
        }
        return Model(meshes: meshes, materials: materials, skippedShapeCount: 0)
    }

    /// Flat 33x33 plane at a constant height for an exterior cell that carries
    /// no LAND record. Height comes from the worldspace WRLD DNAM default land
    /// height (Tamriel -27000); the caller supplies it.
    static func fallbackModel(defaultLandHeight: Float) -> Model {
        let field = Field(
            heights: [Float](repeating: defaultLandHeight, count: Land.vertexCount),
            normals: nil,
            colors: nil
        )
        let patch = Patch(colOrigin: 0, rowOrigin: 0, dimension: gridDimension)
        let mesh = gridMesh(name: "terrain-fallback", patch: patch, materialSlot: 0) { col, row in
            vertex(field: field, col: col, row: row)
        }
        return Model(meshes: [mesh], materials: [.fallback], skippedShapeCount: 0)
    }

    // MARK: - Quadrant geometry

    /// Grid patch (west/south corner + 17-vertex extent) of a quadrant. 0
    /// bottom-left, 1 bottom-right, 2 top-left, 3 top-right (docs/formats/
    /// land.md): bottom = south = low row, left = west = low col. Center row/col
    /// 16 is shared between neighbors.
    private static func quadrantPatch(_ quadrant: UInt8) -> Patch {
        let half = quadrantDimension - 1 // 16
        let origin: (col: Int, row: Int) = switch quadrant {
        case 0: (col: 0, row: 0)
        case 1: (col: half, row: 0)
        case 2: (col: 0, row: half)
        default: (col: half, row: half)
        }
        return Patch(colOrigin: origin.col, rowOrigin: origin.row, dimension: quadrantDimension)
    }

    // MARK: - Grid assembly

    private struct Vertex {
        let position: SIMD3<Float>
        let normal: SIMD3<Float>
        let color: SIMD4<Float>
        let uv: SIMD2<Float>
    }

    /// The full-cell attribute source a patch samples from.
    private struct Field {
        let heights: [Float]
        let normals: [SIMD3<Int8>]?
        let colors: [SIMD3<UInt8>]?
    }

    /// A `dimension`x`dimension` sub-region of the cell grid anchored at its
    /// south-west corner.
    private struct Patch {
        let colOrigin: Int
        let rowOrigin: Int
        let dimension: Int
    }

    /// One grid vertex sampled from the cell field at global (col, row).
    private static func vertex(field: Field, col: Int, row: Int) -> Vertex {
        let index = row * gridDimension + col
        return Vertex(
            position: SIMD3(Float(col) * quadSize, Float(row) * quadSize, field.heights[index]),
            normal: normal(field.normals, at: index),
            color: color(field.colors, at: index),
            uv: uv(col: col, row: row)
        )
    }

    /// Assembles a patch of the cell grid, two triangles per quad wound CCW seen
    /// from above. `vertex` maps a global (col, row) to its attributes.
    private static func gridMesh(
        name: String,
        patch: Patch,
        materialSlot: Int,
        vertex: (_ col: Int, _ row: Int) -> Vertex
    ) -> Mesh {
        let dimension = patch.dimension
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var colors: [SIMD4<Float>] = []
        var uvs: [SIMD2<Float>] = []
        let count = dimension * dimension
        positions.reserveCapacity(count)
        normals.reserveCapacity(count)
        colors.reserveCapacity(count)
        uvs.reserveCapacity(count)
        for localRow in 0 ..< dimension {
            for localCol in 0 ..< dimension {
                let sample = vertex(patch.colOrigin + localCol, patch.rowOrigin + localRow)
                positions.append(sample.position)
                normals.append(sample.normal)
                colors.append(sample.color)
                uvs.append(sample.uv)
            }
        }
        var indices: [UInt16] = []
        indices.reserveCapacity((dimension - 1) * (dimension - 1) * 6)
        for localRow in 0 ..< (dimension - 1) {
            for localCol in 0 ..< (dimension - 1) {
                let sw = UInt16(localRow * dimension + localCol)
                let se = sw + 1
                let nw = UInt16((localRow + 1) * dimension + localCol)
                let ne = nw + 1
                // CCW from +Z (above): SW->SE->NE, SW->NE->NW.
                indices.append(contentsOf: [sw, se, ne, sw, ne, nw])
            }
        }
        return Mesh(
            name: name,
            transform: matrix_identity_float4x4,
            positions: positions,
            normals: normals,
            tangents: [],
            bitangents: [],
            uvs: uvs,
            colors: colors,
            indices: indices,
            materialSlot: materialSlot
        )
    }

    // MARK: - Attribute decode

    /// VNML int8 triple normalized to a unit vector (v/127 then normalize).
    /// Missing normals or a degenerate zero triple fall back to +Z (up).
    private static func normal(_ normals: [SIMD3<Int8>]?, at index: Int) -> SIMD3<Float> {
        guard let normals, index < normals.count else { return SIMD3(0, 0, 1) }
        let raw = normals[index]
        let vector = SIMD3<Float>(Float(raw.x), Float(raw.y), Float(raw.z)) / 127
        let lengthSquared = simd_length_squared(vector)
        guard lengthSquared > .ulpOfOne else { return SIMD3(0, 0, 1) }
        return vector / sqrt(lengthSquared)
    }

    /// VCLR uint8 triple as RGBA in [0, 1], alpha 1. Missing colors -> white.
    private static func color(_ colors: [SIMD3<UInt8>]?, at index: Int) -> SIMD4<Float> {
        guard let colors, index < colors.count else { return SIMD4(1, 1, 1, 1) }
        let raw = colors[index]
        return SIMD4(Float(raw.x) / 255, Float(raw.y) / 255, Float(raw.z) / 255, 1)
    }

    /// UV at a grid position: quads from the cell corner scaled by the
    /// (UNCONFIRMED) tiling density.
    private static func uv(col: Int, row: Int) -> SIMD2<Float> {
        SIMD2(Float(col) / uvQuadsPerRepeat, Float(row) / uvQuadsPerRepeat)
    }
}
