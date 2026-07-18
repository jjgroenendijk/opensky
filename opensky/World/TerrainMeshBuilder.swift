// Build engine terrain patches from a decoded LAND record (todo 3.1 terrain).
// Pure geometry + splat data: one Patch per painted quadrant carrying the
// 17x17 sub-mesh, the BTXT base texture FormID, and the ATXT layers with
// their VTXT opacities baked dense onto the quadrant grid. Texture
// resolution (LTEX -> TXST) and GPU upload live in CellSceneBuilder; the
// splat draw path is documented in docs/rendering/metal4-renderer.md.
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
    /// 289 vertices per quadrant — the VTXT position space (UESP LAND).
    static let quadrantVertexCount = quadrantDimension * quadrantDimension

    /// UV density: grid position in quads scaled by this reciprocal, so one
    /// texture repeat spans `uvQuadsPerRepeat` quads. The exact vanilla tiling
    /// density is UNCONFIRMED (community lore varies) — this constant is a
    /// verifiable starting point, tuned visually against real data.
    static let uvQuadsPerRepeat: Float = 2

    /// One ATXT splat layer of a quadrant, opacities baked dense.
    struct Layer {
        /// LTEX FormID this layer's texture resolves to.
        let texture: FormID
        /// Dense 17x17 opacities (quadrant-grid row-major, clamped [0, 1])
        /// baked from the sparse VTXT samples.
        let opacities: [Float]
    }

    /// One drawable terrain patch: a quadrant sub-mesh (or the LAND-less
    /// fallback plane) plus its splat inputs, pre-resolution.
    struct Patch {
        /// Quadrant index 0-3; nil for the fallback plane.
        let quadrant: UInt8?
        let mesh: Mesh
        /// BTXT LTEX FormID; nil -> quadrant painted with no base (fallback
        /// material downstream).
        let baseTexture: FormID?
        /// ATXT layers sorted by layer number — the splat blend order
        /// (UESP LAND: the layer number drives stacking above the base).
        let layers: [Layer]
    }

    /// Builds the terrain patches for a decoded LAND: one per painted,
    /// non-hidden quadrant. Quadrants whose force-hide bit is set in
    /// `hiddenQuadrants` are skipped (XCLC land-quad flags, UESP CELL) and so
    /// is a LAND with no height data.
    ///
    /// - Parameter hiddenQuadrants: XCLC quad-flags; bit `1 << q` hides
    ///   quadrant q.
    static func patches(land: Land, hiddenQuadrants: UInt32) -> [Patch] {
        guard let heights = land.heightField?.heights, heights.count == Land.vertexCount else {
            return []
        }
        let field = Field(heights: heights, normals: land.normals, colors: land.colors)
        var patches: [Patch] = []
        for quadrant in UInt8(0) ... 3 {
            // UESP CELL XCLC: bits 0x1-0x8 force-hide the matching land quad.
            guard hiddenQuadrants & (1 << UInt32(quadrant)) == 0 else { continue }
            let mesh = gridMesh(
                name: "terrain-quadrant-\(quadrant)",
                patch: quadrantPatch(quadrant)
            ) { col, row in vertex(field: field, col: col, row: row) }
            let layers = land.layers
                .filter { $0.quadrant == quadrant }
                .sorted { $0.layer < $1.layer }
                .map { Layer(texture: $0.texture, opacities: denseOpacities($0.alphas)) }
            patches.append(Patch(
                quadrant: quadrant,
                mesh: mesh,
                baseTexture: land.baseTextures.first { $0.quadrant == quadrant }?.texture,
                layers: layers
            ))
        }
        return patches
    }

    /// Flat 33x33 plane at a constant height for an exterior cell that carries
    /// no LAND record. Height comes from the worldspace WRLD DNAM default land
    /// height (Tamriel -27000); the caller supplies it. No base texture, no
    /// layers — draws with the fallback material and zero weights.
    static func fallbackPatch(defaultLandHeight: Float) -> Patch {
        let field = Field(
            heights: [Float](repeating: defaultLandHeight, count: Land.vertexCount),
            normals: nil,
            colors: nil
        )
        let patch = GridPatch(colOrigin: 0, rowOrigin: 0, dimension: gridDimension)
        let mesh = gridMesh(name: "terrain-fallback", patch: patch) { col, row in
            vertex(field: field, col: col, row: row)
        }
        return Patch(quadrant: nil, mesh: mesh, baseTexture: nil, layers: [])
    }

    // MARK: - Splat weights

    /// Bakes sparse VTXT samples into a dense per-vertex opacity array. Each
    /// entry's position (0-288) indexes the 17x17 quadrant grid row-major
    /// (UESP LAND VTXT) — exactly the vertex order gridMesh emits, so index
    /// `position` maps straight to the quadrant-local vertex. Out-of-range
    /// positions are dropped (external data, mod-quirk rule); opacities are
    /// clamped to [0, 1].
    static func denseOpacities(_ alphas: [Land.AlphaSample]) -> [Float] {
        var dense = [Float](repeating: 0, count: quadrantVertexCount)
        for sample in alphas where Int(sample.position) < quadrantVertexCount {
            dense[Int(sample.position)] = min(max(sample.opacity, 0), 1)
        }
        return dense
    }

    /// Packs per-layer dense opacity arrays into the terrain vertex weight
    /// stream: two float4 lanes per vertex (TerrainVertexLayout), lane order =
    /// blend order, layers beyond TerrainConstant.maxLayers ignored (callers
    /// cap + count first). A layer shorter than `vertexCount` contributes 0
    /// past its end (defensive; bake always emits full arrays).
    static func packWeights(layers: [[Float]], vertexCount: Int) -> [SIMD4<Float>] {
        var packed = [SIMD4<Float>](repeating: .zero, count: vertexCount * 2)
        let capped = layers.prefix(TerrainConstant.maxLayers.rawValue)
        for (layerIndex, opacities) in capped.enumerated() {
            for vertex in 0 ..< min(vertexCount, opacities.count) {
                packed[vertex * 2 + layerIndex / 4][layerIndex % 4] = opacities[vertex]
            }
        }
        return packed
    }

    // MARK: - Quadrant geometry

    /// Grid patch (west/south corner + 17-vertex extent) of a quadrant. 0
    /// bottom-left, 1 bottom-right, 2 top-left, 3 top-right (docs/formats/
    /// land.md): bottom = south = low row, left = west = low col. Center row/col
    /// 16 is shared between neighbors.
    private static func quadrantPatch(_ quadrant: UInt8) -> GridPatch {
        let half = quadrantDimension - 1 // 16
        let origin: (col: Int, row: Int) = switch quadrant {
        case 0: (col: 0, row: 0)
        case 1: (col: half, row: 0)
        case 2: (col: 0, row: half)
        default: (col: half, row: half)
        }
        return GridPatch(colOrigin: origin.col, rowOrigin: origin.row, dimension: quadrantDimension)
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
    private struct GridPatch {
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
    /// from above. `vertex` maps a global (col, row) to its attributes. Vertex
    /// order is patch-local row-major — the same order VTXT positions index,
    /// so baked opacities line up 1:1 with quadrant vertices.
    private static func gridMesh(
        name: String,
        patch: GridPatch,
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
            materialSlot: 0
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
