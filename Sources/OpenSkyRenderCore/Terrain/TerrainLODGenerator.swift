// Builds one terrain LOD block from the winning LAND records: a 33 x 33 grid with
// skirts, a model-space normal map from VNML, and a diffuse map baked from the texture
// layers and VCLR. docs/engine/distant-lod.md#generated-terrain has the rules.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import simd

nonisolated public enum TerrainLODGenerator {
    /// Quads along each side of a block at every level, as vanilla's level 4 has about.
    public static let quadsPerSide = 32
    /// Vanilla blocks have 256 x 256 maps at every level.
    public static let textureSize = 256
    /// Where a cell has no land; dark, as the sea floor under LOD water.
    static let missingColour = SIMD3<Float>(0.05, 0.05, 0.05)

    /// What one block reads: its level and the land of each of its cells.
    public struct Source: Sendable {
        public let level: Int32
        /// Row-major from the south-west cell; nil where a cell has no land.
        public let cells: [TerrainLODLand?]
        /// The worldspace's default land height, for cells without land.
        public let defaultHeight: Float

        public init(level: Int32, cells: [TerrainLODLand?], defaultHeight: Float) {
            self.level = level
            self.cells = cells
            self.defaultHeight = defaultHeight
        }

        var size: Float {
            Float(level) * TerrainMeshBuilder.cellSize
        }

        /// The cell under a block-local point, and the point in that cell's quads.
        func locate(_ point: SIMD2<Float>) -> (land: TerrainLODLand?, quads: SIMD2<Float>) {
            let cellSize = TerrainMeshBuilder.cellSize
            let last = Int(level) - 1
            let column = min(max(Int(point.x / cellSize), 0), last)
            let row = min(max(Int(point.y / cellSize), 0), last)
            let local = (point - SIMD2(Float(column), Float(row)) * cellSize)
                / TerrainMeshBuilder.quadSize
            let index = row * Int(level) + column
            return (index < cells.count ? cells[index] : nil, local)
        }

        func height(at point: SIMD2<Float>) -> Float {
            let found = locate(point)
            return found.land?.height(x: found.quads.x, y: found.quads.y) ?? defaultHeight
        }
    }

    /// Vanilla hangs skirts 1000 units deep at level 4, 2000 at 8, 3000 at 16, 4000 at 32.
    public static func skirtDepth(level: Int32) -> Float {
        Float(max(level.trailingZeroBitCount - 1, 1)) * 1000
    }

    /// The block in block-local units, with a skirt under each side.
    public static func model(_ source: Source, diffuseKey: String, normalKey: String) -> Model {
        let side = quadsPerSide + 1
        var positions: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        for row in 0 ..< side {
            for column in 0 ..< side {
                let share = SIMD2(Float(column), Float(row)) / Float(quadsPerSide)
                let point = share * source.size
                positions.append(SIMD3(point, source.height(at: point)))
                uvs.append(SIMD2(share.x, 1 - share.y))
            }
        }
        var indices: [UInt16] = []
        for row in 0 ..< quadsPerSide {
            for column in 0 ..< quadsPerSide {
                let southWest = UInt16(row * side + column)
                let northWest = southWest + UInt16(side)
                indices += [
                    southWest,
                    southWest + 1,
                    northWest + 1,
                    southWest,
                    northWest + 1,
                    northWest
                ]
            }
        }
        appendSkirts(&positions, &uvs, &indices, depth: skirtDepth(level: source.level))
        let count = positions.count
        let mesh = Mesh(
            name: "land",
            transform: matrix_identity_float4x4,
            positions: positions,
            normals: Array(repeating: SIMD3(0, 0, 1), count: count),
            tangents: Array(repeating: SIMD3(1, 0, 0), count: count),
            bitangents: Array(repeating: SIMD3(0, 1, 0), count: count),
            uvs: uvs,
            colors: Array(repeating: SIMD4(1, 1, 1, 1), count: count),
            indices: indices,
            materialSlot: 0
        )
        return Model(
            meshes: [mesh],
            materials: [material(diffuseKey, normalKey)],
            skippedShapeCount: 0
        )
    }

    /// A strip down from each outer edge, drawn from both sides, so a coarser neighbour's
    /// lower edge shows no gap.
    private static func appendSkirts(
        _ positions: inout [SIMD3<Float>],
        _ uvs: inout [SIMD2<Float>],
        _ indices: inout [UInt16],
        depth: Float
    ) {
        let side = quadsPerSide + 1
        let edges: [[Int]] = [
            (0 ..< side).map(\.self),
            (0 ..< side).map { (side - 1) * side + $0 },
            (0 ..< side).map { $0 * side },
            (0 ..< side).map { $0 * side + side - 1 }
        ]
        for edge in edges {
            let first = positions.count
            for top in edge {
                positions.append(positions[top] - SIMD3(0, 0, depth))
                uvs.append(uvs[top])
            }
            for step in 0 ..< edge.count - 1 {
                let upper = (UInt16(edge[step]), UInt16(edge[step + 1]))
                let lower = (UInt16(first + step), UInt16(first + step + 1))
                indices += [upper.0, lower.0, lower.1, upper.0, lower.1, upper.1]
                indices += [upper.0, lower.1, lower.0, upper.0, upper.1, lower.1]
            }
        }
    }

    /// Lit like vanilla terrain LOD: no specular, normals from a model-space map.
    private static func material(_ diffuseKey: String, _ normalKey: String) -> Material {
        var shading = SurfaceShading()
        shading.terms = [.modelSpaceNormals]
        return Material(
            diffuseTexture: diffuseKey,
            normalTexture: normalKey,
            uvOffset: .zero,
            uvScale: SIMD2(1, 1),
            alpha: 1,
            glossiness: 80,
            specularColor: SIMD3(1, 1, 1),
            specularStrength: 0,
            doubleSided: false,
            alphaBlend: false,
            alphaTestThreshold: nil,
            shading: shading
        )
    }

    /// The block-local point at the centre of a map texel; row 0 is the north edge.
    static func texelPoint(column: Int, row: Int, source: Source) -> SIMD2<Float> {
        let size = Float(textureSize)
        let share = SIMD2((Float(column) + 0.5) / size, 1 - (Float(row) + 0.5) / size)
        return share * source.size
    }

    /// RGBA8, model-space normals with x in red, z in green, and y in blue, as the lit
    /// shader reads them. Alpha 0: no specular.
    public static func normalMap(_ source: Source) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: textureSize * textureSize * 4)
        for row in 0 ..< textureSize {
            for column in 0 ..< textureSize {
                let found = source.locate(texelPoint(column: column, row: row, source: source))
                let normal = found.land?.normal(x: found.quads.x, y: found.quads.y)
                    ?? SIMD3(0, 0, 1)
                let encoded = SIMD3(normal.x, normal.z, normal.y) * 0.5 + 0.5
                let base = (row * textureSize + column) * 4
                pixels[base] = TerrainLODTexture.byte(encoded.x)
                pixels[base + 1] = TerrainLODTexture.byte(encoded.y)
                pixels[base + 2] = TerrainLODTexture.byte(encoded.z)
            }
        }
        return pixels
    }
}
