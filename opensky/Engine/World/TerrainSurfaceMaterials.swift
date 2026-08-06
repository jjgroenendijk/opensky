// What exterior ground is made of, per terrain vertex (issue #358).
//
// Terrain is the case the Havok material chain cannot answer. Exterior ground
// is a LAND record rather than a collision mesh, so it carries no Havok
// material at all: it names its surface through the landscape textures painted
// on it, each LTEX pointing at a MATT with its MNAM. A cell's ground is
// therefore as many materials as it has textures, varying inside one quadrant
// wherever a layer is painted.
//
// This resolves that at build time into one MATT per terrain vertex, the same
// 33x33 grid the height field uses. It is the splat blend the terrain shader
// runs, kept as per-texture weights instead of a colour, with the heaviest
// texture at each vertex winning — the material under the foot is the one the
// player sees most of there.

import simd

nonisolated struct TerrainSurfaceMaterials: Equatable, Sendable {
    /// One MATT FormID per terrain vertex, row-major south->north /
    /// west->east like `TerrainHeightField.heights`. Nil where the winning
    /// texture names no material, or where nothing is painted at all.
    let materials: [FormID?]

    init?(materials: [FormID?]) {
        guard materials.count == Land.vertexCount else { return nil }
        self.materials = materials
    }

    /// The material at a terrain grid position, clamped to the grid.
    func material(column: Int, row: Int) -> FormID? {
        let dimension = TerrainMeshBuilder.gridDimension
        let clampedColumn = min(max(column, 0), dimension - 1)
        let clampedRow = min(max(row, 0), dimension - 1)
        return materials[clampedRow * dimension + clampedColumn]
    }

    /// One quadrant's splat stack, base first, each layer's opacities baked
    /// dense onto the 17x17 quadrant grid.
    private struct Quadrant {
        let base: FormID?
        let layers: [TerrainMeshBuilder.Layer]

        var isPainted: Bool {
            base != nil || !layers.isEmpty
        }

        /// The texture with the most weight at one quadrant vertex, from the
        /// same ordered lerps the terrain fragment shader runs: each layer
        /// scales what is already there down by its own opacity and adds
        /// itself on top. A tie goes to the later layer, which is the one
        /// drawn over the other.
        func winningTexture(at position: Int) -> FormID? {
            var weights: [FormID: Float] = [:]
            var blendOrder: [FormID: Int] = [:]
            if let base {
                weights[base] = 1
                blendOrder[base] = 0
            }
            for (index, layer) in layers.enumerated() {
                guard position < layer.opacities.count else { continue }
                let opacity = layer.opacities[position]
                for texture in weights.keys {
                    weights[texture, default: 0] *= 1 - opacity
                }
                weights[layer.texture, default: 0] += opacity
                blendOrder[layer.texture] = index + 1
            }
            return weights.max { first, second in
                first.value == second.value
                    ? (blendOrder[first.key] ?? 0) < (blendOrder[second.key] ?? 0)
                    : first.value < second.value
            }?.key
        }
    }

    /// Builds the grid for one LAND. Returns nil when the record paints
    /// nothing this could resolve, so a caller keeps a height field with no
    /// material rather than one claiming every vertex is unpainted.
    static func build(land: Land, materialTypes: MaterialTypeIndex) -> TerrainSurfaceMaterials? {
        let dimension = TerrainMeshBuilder.gridDimension
        var resolved = [FormID?](repeating: nil, count: Land.vertexCount)
        var painted = false
        for index in UInt8(0) ... 3 {
            let quadrant = quadrant(index, in: land)
            guard quadrant.isPainted else { continue }
            let origin = quadrantOrigin(index)
            for row in 0 ..< TerrainMeshBuilder.quadrantDimension {
                for column in 0 ..< TerrainMeshBuilder.quadrantDimension {
                    let local = row * TerrainMeshBuilder.quadrantDimension + column
                    guard
                        let texture = quadrant.winningTexture(at: local),
                        let material = materialTypes.material(forLandTexture: texture)
                    else { continue }
                    painted = true
                    resolved[(origin.row + row) * dimension + origin.column + column] = material
                }
            }
        }
        return painted ? TerrainSurfaceMaterials(materials: resolved) : nil
    }

    private static func quadrant(_ index: UInt8, in land: Land) -> Quadrant {
        Quadrant(
            base: land.baseTextures.first { $0.quadrant == index }?.texture,
            layers: land.layers
                .filter { $0.quadrant == index }
                .sorted { $0.layer < $1.layer }
                .map {
                    TerrainMeshBuilder.Layer(
                        texture: $0.texture,
                        opacities: TerrainMeshBuilder.denseOpacities($0.alphas)
                    )
                }
        )
    }

    /// South-west corner of a quadrant on the full-cell grid. Matches
    /// `TerrainMeshBuilder`'s quadrant patches: quadrants share the centre row
    /// and column, and later quadrants overwrite it, which is harmless because
    /// both painted it from the same LAND.
    private static func quadrantOrigin(_ quadrant: UInt8) -> (column: Int, row: Int) {
        let half = TerrainMeshBuilder.quadrantDimension - 1
        return switch quadrant {
        case 0: (column: 0, row: 0)
        case 1: (column: half, row: 0)
        case 2: (column: 0, row: half)
        default: (column: half, row: half)
        }
    }
}
