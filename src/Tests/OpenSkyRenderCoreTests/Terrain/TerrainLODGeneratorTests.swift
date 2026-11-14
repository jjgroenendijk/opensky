// Generated terrain LOD from synthetic land: the block grid and skirts, cells without
// land, the diffuse bake with layers and VCLR, and the normal map encoding.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyRenderCore
import simd
import Testing

struct TerrainLODGeneratorTests {
    private static let red = FormID(0x100)
    private static let blue = FormID(0x200)

    private static func land(
        height: Float,
        normal: SIMD3<Float> = SIMD3(0, 0, 1),
        colour: SIMD3<Float> = SIMD3(1, 1, 1),
        layerOpacity: Float? = nil
    ) -> TerrainLODLand {
        let count = Land.vertexCount
        let quadrant = TerrainLODLand.Quadrant(
            base: red,
            layers: layerOpacity.map {
                [(blue, [Float](repeating: $0, count: TerrainMeshBuilder.quadrantVertexCount))]
            } ?? []
        )
        return TerrainLODLand(
            heights: Array(repeating: height, count: count),
            normals: Array(repeating: normal, count: count),
            colours: Array(repeating: colour, count: count),
            quadrants: Array(repeating: quadrant, count: 4)
        )
    }

    private static func texture(_ colour: SIMD3<UInt8>) -> TerrainLODTexture? {
        TerrainLODTexture(
            width: 2, height: 2,
            rgba: Array([colour.x, colour.y, colour.z, 255].map(\.self).repeated(4))
        )
    }

    private static func textures(_ form: FormID) -> TerrainLODTexture? {
        form == red ? texture(SIMD3(255, 0, 0)) : texture(SIMD3(0, 0, 255))
    }

    @Test func blockGridSpansTheBlockAndHangsSkirts() throws {
        var cells = [TerrainLODLand?](repeating: Self.land(height: 100), count: 16)
        cells[1] = Self.land(height: 500)
        let source = TerrainLODGenerator.Source(level: 4, cells: cells, defaultHeight: -2048)
        let model = TerrainLODGenerator.model(source, diffuseKey: "d", normalKey: "n")
        let mesh = try #require(model.meshes.first)
        let side = TerrainLODGenerator.quadsPerSide + 1
        #expect(mesh.positions.count == side * side + 4 * side)
        #expect(mesh.positions[side * side - 1] == SIMD3(16384, 16384, 100))
        // Vertex 12 lies at x 6144, inside cell (1, 0).
        #expect(mesh.positions[12].z == 500)
        let lowest = try #require(mesh.positions.map(\.z).min())
        #expect(lowest == 100 - 1000)
        #expect(model.materials.first?.diffuseTexture == "d")
        #expect(model.materials.first?.shading.terms.contains(.modelSpaceNormals) == true)
    }

    @Test func cellWithoutLandTakesTheDefaultHeight() {
        var cells = [TerrainLODLand?](repeating: Self.land(height: 100), count: 16)
        cells[0] = nil
        let source = TerrainLODGenerator.Source(level: 4, cells: cells, defaultHeight: -2048)
        #expect(source.height(at: SIMD2(100, 100)) == -2048)
        #expect(source.height(at: SIMD2(5000, 100)) == 100)
    }

    @Test func skirtDepthAndTextureEdgeFollowTheLevel() {
        #expect([4, 8, 16, 32].map { TerrainLODGenerator.skirtDepth(level: $0) }
            == [1000, 2000, 3000, 4000])
        #expect([4, 8, 16, 32].map { TerrainLODGenerator.textureEdge(level: $0) } == [8, 4, 2, 1])
    }

    @Test func diffuseBlendsLayersAndMultipliesVertexColour() {
        let plain = TerrainLODGenerator.Source(
            level: 4, cells: Array(repeating: Self.land(height: 0), count: 16), defaultHeight: 0
        )
        let base = TerrainLODGenerator.diffuse(plain, texture: Self.textures)
        #expect(Array(base[0 ..< 4]) == [255, 0, 0, 255])
        let layered = TerrainLODGenerator.Source(
            level: 4,
            cells: Array(
                repeating: Self.land(height: 0, colour: SIMD3(0.5, 0.5, 0.5), layerOpacity: 1),
                count: 16
            ),
            defaultHeight: 0
        )
        let blended = TerrainLODGenerator.diffuse(layered, texture: Self.textures)
        // Linear blue times 0.5^2.2, then encoded to sRGB again: about 0.5 in sRGB.
        #expect(blended[0] == 0)
        #expect((120 ... 135).contains(blended[2]))
    }

    /// The bake written as plainly as possible: every sample looks its textures up.
    private static func oracleDiffuse(
        _ source: TerrainLODGenerator.Source,
        texture: (FormID) -> TerrainLODTexture?
    ) -> [UInt8] {
        let side = TerrainLODGenerator.textureSize
        var pixels = [UInt8](repeating: 255, count: side * side * 4)
        let texel = source.size / Float(side)
        for row in 0 ..< side {
            for column in 0 ..< side {
                let centre = TerrainLODGenerator.texelPoint(
                    column: column,
                    row: row,
                    source: source
                )
                var sum = SIMD3<Float>(repeating: 0)
                for offset in [
                    SIMD2<Float>(-0.25, -0.25),
                    SIMD2(0.25, -0.25),
                    SIMD2(-0.25, 0.25),
                    SIMD2(0.25, 0.25)
                ] {
                    let found = source.locate(centre + offset * texel)
                    guard let land = found.land else {
                        sum += TerrainLODGenerator.missingColour
                        continue
                    }
                    let quads = found.quads
                    let east = quads.x >= 16 ? 1 : 0
                    let north = quads.y >= 16 ? 1 : 0
                    let quadrant = land.quadrants[north * 2 + east]
                    let local = quads - SIMD2(Float(east), Float(north)) * 16
                    let (u, v) = (quads.x / 2, quads.y / 2)
                    var albedo = texture(quadrant.base)?.sample(u: u, v: v)
                        ?? TerrainLODGenerator.missingColour
                    for layer in quadrant.layers {
                        guard let map = texture(layer.texture) else { continue }
                        let weight = TerrainLODGenerator.quadrantOpacity(layer.opacities, at: local)
                        if weight > 0 {
                            albedo = simd_mix(
                                albedo,
                                map.sample(u: u, v: v),
                                SIMD3(repeating: weight)
                            )
                        }
                    }
                    let tint = TerrainLODLand.bilinear(x: quads.x, y: quads.y) { land.colours[$0] }
                    sum += albedo * SIMD3(pow(tint.x, 2.2), pow(tint.y, 2.2), pow(tint.z, 2.2))
                }
                let mean = sum / 4
                let base = (row * side + column) * 4
                for channel in 0 ..< 3 {
                    pixels[base + channel] = TerrainLODTexture.byte(
                        TerrainLODTexture.encoded(mean[channel])
                    )
                }
            }
        }
        return pixels
    }

    @Test func theBakeMatchesAPlainPerSampleBake() {
        let missing = FormID(0x300)
        var cells = [TerrainLODLand?](repeating: Self.land(height: 0), count: 16)
        cells[2] = Self.land(height: 0, colour: SIMD3(0.8, 0.4, 0.2), layerOpacity: 0.6)
        cells[7] = nil
        cells[9] = TerrainLODLand(
            heights: Array(repeating: 0, count: Land.vertexCount),
            normals: Array(repeating: SIMD3(0, 0, 1), count: Land.vertexCount),
            colours: (0 ..< Land.vertexCount).map { SIMD3(Float($0 % 7) / 7, 0.5, 1) },
            quadrants: Array(repeating: TerrainLODLand.Quadrant(
                base: Self.blue,
                layers: [
                    (missing, [Float](repeating: 1, count: TerrainMeshBuilder.quadrantVertexCount)),
                    (Self.red, (0 ..< TerrainMeshBuilder.quadrantVertexCount).map {
                        Float($0 % 17) / 16
                    })
                ]
            ), count: 4)
        )
        let source = TerrainLODGenerator.Source(level: 4, cells: cells, defaultHeight: 0)
        let textures: (FormID) -> TerrainLODTexture? = { $0 == missing ? nil : Self.textures($0) }
        #expect(
            TerrainLODGenerator.diffuse(source, texture: textures)
                == Self.oracleDiffuse(source, texture: textures)
        )
    }

    @Test func textureFormsListEveryBaseAndLayerOnce() {
        var cells = [TerrainLODLand?](repeating: Self.land(height: 0), count: 16)
        cells[3] = Self.land(height: 0, layerOpacity: 0.5)
        cells[5] = nil
        let source = TerrainLODGenerator.Source(level: 4, cells: cells, defaultHeight: 0)
        #expect(TerrainLODGenerator.textureForms(of: source) == [Self.red, Self.blue])
        let bare = TerrainLODGenerator.Source(
            level: 4, cells: Array(repeating: nil, count: 16), defaultHeight: 0
        )
        #expect(TerrainLODGenerator.textureForms(of: bare).isEmpty)
    }

    @Test func normalMapStoresXZYInRedGreenBlue() {
        let source = TerrainLODGenerator.Source(
            level: 4,
            cells: Array(repeating: Self.land(height: 0, normal: SIMD3(1, 0, 0)), count: 16),
            defaultHeight: 0
        )
        let pixels = TerrainLODGenerator.normalMap(source)
        #expect(Array(pixels[0 ..< 4]) == [255, 128, 128, 0])
    }
}

extension Array {
    fileprivate func repeated(_ count: Int) -> [Element] {
        (0 ..< count).flatMap { _ in self }
    }
}
