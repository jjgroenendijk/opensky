// The diffuse map of a generated terrain LOD block. Each texel blends the quadrant's
// base texture and its layers by their VTXT opacity in linear light, as the near terrain
// shader does, then multiplies the VCLR colour (docs/engine/distant-lod.md).

import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import simd

/// A land texture at a small mip, in linear light, sampled with wrap.
nonisolated public struct TerrainLODTexture: Sendable {
    public let width: Int
    public let height: Int
    let texels: [SIMD3<Float>]

    /// `rgba` is sRGB-encoded RGBA8, row 0 first.
    public init?(width: Int, height: Int, rgba: [UInt8]) {
        guard width > 0, height > 0, rgba.count >= width * height * 4 else { return nil }
        self.width = width
        self.height = height
        texels = (0 ..< width * height).map { index in
            SIMD3(
                Self.linear(rgba[index * 4]), Self.linear(rgba[index * 4 + 1]),
                Self.linear(rgba[index * 4 + 2])
            )
        }
    }

    /// Bilinear with wrap; `u` and `v` in texture repeats.
    func sample(u: Float, v: Float) -> SIMD3<Float> {
        let x = (u - u.rounded(.down)) * Float(width) - 0.5
        let y = (v - v.rounded(.down)) * Float(height) - 0.5
        let column = Int(x.rounded(.down))
        let row = Int(y.rounded(.down))
        let fx = x - Float(column)
        let fy = y - Float(row)
        func texel(_ across: Int, _ down: Int) -> SIMD3<Float> {
            let wrappedColumn = ((across % width) + width) % width
            let wrappedRow = ((down % height) + height) % height
            return texels[wrappedRow * width + wrappedColumn]
        }
        let top = simd_mix(texel(column, row), texel(column + 1, row), SIMD3(repeating: fx))
        let bottom = simd_mix(
            texel(column, row + 1), texel(column + 1, row + 1), SIMD3(repeating: fx)
        )
        return simd_mix(top, bottom, SIMD3(repeating: fy))
    }

    static func linear(_ byte: UInt8) -> Float {
        let value = Float(byte) / 255
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    static func encoded(_ value: Float) -> Float {
        let clamped = min(max(value, 0), 1)
        return clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
    }

    static func byte(_ value: Float) -> UInt8 {
        UInt8(min(max(value, 0), 1) * 255 + 0.5)
    }
}

nonisolated extension TerrainLODGenerator {
    /// A texture repeats every 2 quads, as on the near terrain.
    static let quadsPerRepeat: Float = 2

    /// The mip edge a texture needs at `level`: each map texel spans `16 × level` units,
    /// so a 256-unit repeat holds `16 / level` texels. Twice that, for the 2 x 2 samples.
    public static func textureEdge(level: Int32) -> Int {
        max(32 / Int(max(level, 1)), 1)
    }

    /// Every land texture the diffuse bake of `source` can ask for.
    public static func textureForms(of source: Source) -> Set<FormID> {
        var forms: Set<FormID> = []
        for land in source.cells.compactMap(\.self) {
            for quadrant in land.quadrants {
                forms.insert(quadrant.base)
                for layer in quadrant.layers {
                    forms.insert(layer.texture)
                }
            }
        }
        return forms
    }

    /// RGBA8 in sRGB, row 0 at the north edge, alpha 255. `texture` gives a land texture
    /// at `textureEdge(level:)`; nil leaves that layer out.
    public static func diffuse(
        _ source: Source,
        texture: (FormID) -> TerrainLODTexture?
    ) -> [UInt8] {
        let lands = BakeLand.resolve(source.cells, texture: texture)
        var pixels = [UInt8](repeating: 255, count: textureSize * textureSize * 4)
        let offsets: [SIMD2<Float>] = [
            SIMD2(-0.25, -0.25),
            SIMD2(0.25, -0.25),
            SIMD2(-0.25, 0.25),
            SIMD2(0.25, 0.25)
        ]
        let texel = source.size / Float(textureSize)
        for row in 0 ..< textureSize {
            for column in 0 ..< textureSize {
                let centre = texelPoint(column: column, row: row, source: source)
                var sum = SIMD3<Float>(repeating: 0)
                for offset in offsets {
                    sum += colour(at: centre + offset * texel, source: source, lands: lands)
                }
                let base = (row * textureSize + column) * 4
                let mean = sum / Float(offsets.count)
                pixels[base] = TerrainLODTexture.byte(TerrainLODTexture.encoded(mean.x))
                pixels[base + 1] = TerrainLODTexture.byte(TerrainLODTexture.encoded(mean.y))
                pixels[base + 2] = TerrainLODTexture.byte(TerrainLODTexture.encoded(mean.z))
            }
        }
        return pixels
    }

    /// The linear colour of the land at one block-local point.
    static func colour(
        at point: SIMD2<Float>,
        source: Source,
        lands: [BakeLand?]
    ) -> SIMD3<Float> {
        let found = source.locateCell(point)
        guard found.index < lands.count, let land = lands[found.index] else {
            return missingColour
        }
        let quads = found.quads
        let east = quads.x >= 16 ? 1 : 0
        let north = quads.y >= 16 ? 1 : 0
        let quadrant = land.quadrants[north * 2 + east]
        let local = quads - SIMD2(Float(east), Float(north)) * 16
        let u = quads.x / quadsPerRepeat
        let v = quads.y / quadsPerRepeat
        var albedo = quadrant.base?.sample(u: u, v: v) ?? missingColour
        for layer in quadrant.layers {
            let weight = quadrantOpacity(layer.opacities, at: local)
            if weight > 0 {
                albedo = simd_mix(albedo, layer.map.sample(u: u, v: v), SIMD3(repeating: weight))
            }
        }
        let vertexColour = TerrainLODLand.bilinear(x: quads.x, y: quads.y) { land.colours[$0] }
        return albedo * SIMD3(
            pow(vertexColour.x, 2.2), pow(vertexColour.y, 2.2), pow(vertexColour.z, 2.2)
        )
    }

    /// Bilinear on the 17 x 17 quadrant grid.
    static func quadrantOpacity(_ opacities: [Float], at local: SIMD2<Float>) -> Float {
        let side = TerrainMeshBuilder.quadrantDimension
        guard opacities.count >= side * side else { return 0 }
        let x = min(max(local.x, 0), Float(side - 1))
        let y = min(max(local.y, 0), Float(side - 1))
        let column = min(Int(x), side - 2)
        let row = min(Int(y), side - 2)
        let fx = x - Float(column)
        let fy = y - Float(row)
        let index = row * side + column
        let south = opacities[index] + (opacities[index + 1] - opacities[index]) * fx
        let north = opacities[index + side] +
            (opacities[index + side + 1] - opacities[index + side]) * fx
        return min(max(south + (north - south) * fy, 0), 1)
    }
}

/// One cell's land with its textures looked up once per block, so a sample reads no
/// dictionary and calls no closure.
nonisolated struct BakeLand {
    struct Quadrant {
        let base: TerrainLODTexture?
        /// Only the layers whose texture exists, in blend order.
        let layers: [(map: TerrainLODTexture, opacities: [Float])]
    }

    let colours: [SIMD3<Float>]
    let quadrants: [Quadrant]

    static func resolve(
        _ cells: [TerrainLODLand?],
        texture: (FormID) -> TerrainLODTexture?
    ) -> [Self?] {
        var cache: [FormID: TerrainLODTexture?] = [:]
        func lookup(_ form: FormID) -> TerrainLODTexture? {
            if let hit = cache[form] {
                return hit
            }
            let made = texture(form)
            cache[form] = made
            return made
        }
        return cells.map { cell in
            cell.map { land in
                Self(colours: land.colours, quadrants: land.quadrants.map { quadrant in
                    Quadrant(
                        base: lookup(quadrant.base),
                        layers: quadrant.layers.compactMap { layer in
                            lookup(layer.texture).map { ($0, layer.opacities) }
                        }
                    )
                })
            }
        }
    }
}
