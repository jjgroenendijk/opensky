// The mean colour of one cell's land as LAND paints it: the base texture of each
// quadrant, each ATXT layer blended over it by its VTXT opacity, times VCLR.
// Values are gamma, 0 to 1, as the terrain LOD textures store them.

import OpenSkyFormatsESM
import simd

nonisolated public enum TerrainCellAlbedo {
    private static let quadrantSide = 17

    /// Nil for a cell without painted textures or with an unresolvable base texture.
    /// `textureMean` gives the mean diffuse colour of an LTEX, the null FormID included.
    public static func mean(
        land: Land,
        textureMean: (FormID) -> SIMD3<Float>?
    ) -> SIMD3<Float>? {
        let painted = !land.layers.isEmpty || land.baseTextures.contains { !$0.texture.isNull }
        guard painted else { return nil }
        var total = SIMD3<Float>(repeating: 0)
        for quadrant in UInt8(0) ..< 4 {
            guard let base = textureMean(land.baseTexture(quadrant: quadrant)) else { return nil }
            total += quadrantSum(land: land, quadrant: quadrant, base: base, textureMean)
        }
        return total / Float(4 * quadrantSide * quadrantSide)
    }

    private static func quadrantSum(
        land: Land,
        quadrant: UInt8,
        base: SIMD3<Float>,
        _ textureMean: (FormID) -> SIMD3<Float>?
    ) -> SIMD3<Float> {
        let side = quadrantSide
        var colours = [SIMD3<Float>](repeating: base, count: side * side)
        let layers = land.layers.filter { $0.quadrant == quadrant }.sorted { $0.layer < $1.layer }
        for layer in layers {
            guard let mean = textureMean(layer.texture) else { continue }
            for sample in layer.alphas where Int(sample.position) < colours.count {
                let index = Int(sample.position)
                colours[index] = simd_mix(colours[index], mean, SIMD3(repeating: sample.opacity))
            }
        }
        let originX = Int(quadrant & 1) * (side - 1)
        let originY = Int(quadrant >> 1) * (side - 1)
        var sum = SIMD3<Float>(repeating: 0)
        for row in 0 ..< side {
            for column in 0 ..< side {
                var colour = colours[row * side + column]
                if let vertexColours = land.colors {
                    let index = (originY + row) * Land.dimension + originX + column
                    if index < vertexColours.count {
                        colour *= SIMD3<Float>(vertexColours[index]) / 255
                    }
                }
                sum += colour
            }
        }
        return sum
    }
}
