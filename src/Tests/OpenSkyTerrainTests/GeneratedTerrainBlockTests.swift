// One generated terrain block baked from flat land: both maps decode at the bake size.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyImageKernels
import OpenSkyRenderCore
@testable import OpenSkyTerrain
import Testing

struct GeneratedTerrainBlockTests {
    @Test func aBlockBakesBothMapsAtTheBakeSize() throws {
        let count = Land.vertexCount
        let land = TerrainLODLand(
            heights: Array(repeating: 0, count: count),
            normals: Array(repeating: SIMD3(0, 0, 1), count: count),
            colours: Array(repeating: SIMD3(1, 1, 1), count: count),
            quadrants: Array(repeating: .init(base: FormID(0x100), layers: []), count: 4)
        )
        let block = DistantLODBlock(
            kind: .terrain, level: 4, origin: CellCoordinate(x: 0, y: 0),
            path: "meshes\\terrain\\tamriel\\tamriel.4.0.0.btr", clipMask: nil
        )
        let source = TerrainLODGenerator.Source(
            level: 4, cells: [land] + Array(repeating: nil, count: 15), defaultHeight: 0
        )
        let made = GeneratedTerrainBlock(block, from: source) { _ in nil }
        let side = TerrainLODGenerator.textureSize
        let diffuse = try DDSDecoder.topLevel(made.diffuse)
        let normal = try DDSDecoder.topLevel(made.normal)
        #expect(diffuse.width == side && diffuse.height == side)
        #expect(normal.width == side && normal.height == side)
    }
}
