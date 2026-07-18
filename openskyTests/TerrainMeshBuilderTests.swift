// TerrainMeshBuilder tests over synthetic in-code LAND values (built via the
// same helpers as TerrainRecordDecoderTests) — never extracted game files
// (AGENTS.md "Legal & IP boundary"). Verify grid geometry (128-unit quads,
// height passthrough), VNML normalization, per-quadrant topology + shared
// edges, hidden-quadrant omission, the LAND-less fallback plane, and the
// splat inputs: base/layer routing, VTXT dense bake, weight packing.

import Foundation
@testable import opensky
import simd
import Testing

struct TerrainMeshBuilderTests {
    // MARK: - Land fixtures

    /// One synthetic ATXT+VTXT layer for the fixture below.
    private struct LayerSpec {
        let quadrant: UInt8
        let layer: Int16
        let formID: UInt32
        let samples: [(position: UInt16, opacity: Float)]
    }

    /// A LAND with a flat height field at `height` game units, optional VNML
    /// triple applied to every vertex, a BTXT base per listed quadrant, and
    /// optional ATXT/VTXT layers.
    private func land(
        height: Float = 0,
        normal: SIMD3<Int8>? = nil,
        baseQuadrants: [UInt8] = [0, 1, 2, 3],
        layers: [LayerSpec] = []
    ) throws -> Land {
        // Height field: anchor set so every accumulated vertex equals height/8
        // (flat -> only the row-0 col-0 delta carries; keep deltas zero and put
        // the value in the anchor). Decoder scales *8, so anchor = height/8.
        var data = Data()
        data.appendFloat32(height / 8)
        data.append(contentsOf: [UInt8](repeating: 0, count: Land.vertexCount))
        data.append(contentsOf: [0, 0, 0])
        var fields = ESMFixture.field("VHGT", data)
        if let normal {
            var vnml = Data()
            for _ in 0 ..< Land.vertexCount {
                vnml.append(UInt8(bitPattern: normal.x))
                vnml.append(UInt8(bitPattern: normal.y))
                vnml.append(UInt8(bitPattern: normal.z))
            }
            fields += ESMFixture.field("VNML", vnml)
        }
        for quadrant in baseQuadrants {
            var btxt = Data()
            btxt.appendUInt32(0x1000 + UInt32(quadrant))
            btxt.append(quadrant)
            btxt.append(0)
            btxt.appendUInt16(0)
            fields += ESMFixture.field("BTXT", btxt)
        }
        for spec in layers {
            var atxt = Data()
            atxt.appendUInt32(spec.formID)
            atxt.append(spec.quadrant)
            atxt.append(0)
            atxt.appendUInt16(UInt16(bitPattern: spec.layer))
            fields += ESMFixture.field("ATXT", atxt)
            var vtxt = Data()
            for sample in spec.samples {
                vtxt.appendUInt16(sample.position)
                vtxt.appendUInt16(0)
                vtxt.appendFloat32(sample.opacity)
            }
            fields += ESMFixture.field("VTXT", vtxt)
        }
        let bytes = ESMFixture.record("LAND", data: fields)
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a LAND record")
        }
        return try Land(record: record)
    }

    // MARK: - Geometry

    @Test func buildsFourQuadrantsWithSharedEdgeVertices() throws {
        let patches = try TerrainMeshBuilder.patches(land: land(), hiddenQuadrants: 0)
        #expect(patches.count == 4)
        for patch in patches {
            // 17x17 vertices, 16x16 quads * 2 triangles * 3 indices.
            #expect(patch.mesh.positions.count == 17 * 17)
            #expect(patch.mesh.indices.count == 16 * 16 * 6)
            #expect(patch.mesh.indices.allSatisfy { $0 < UInt16(patch.mesh.positions.count) })
        }
        // Quadrant 0 (SW) and quadrant 1 (SE) share the center column (col 16):
        // q0's east edge equals q1's west edge in world position.
        let q0 = patches[0].mesh
        let q1 = patches[1].mesh
        for row in 0 ..< 17 {
            let q0East = q0.positions[row * 17 + 16] // col 16 within q0
            let q1West = q1.positions[row * 17 + 0] // col 16 globally, local 0
            #expect(q0East == q1West)
        }
    }

    @Test func mapsGridToWorldWithQuadSizeAndHeight() throws {
        let patches = try TerrainMeshBuilder.patches(land: land(height: 800), hiddenQuadrants: 0)
        let q0 = patches[0].mesh
        // Local (col, row) -> world (col*128, row*128, height). Flat at 800.
        #expect(q0.positions[0] == SIMD3(0, 0, 800)) // col 0, row 0
        #expect(q0.positions[1] == SIMD3(128, 0, 800)) // col 1, row 0
        #expect(q0.positions[17] == SIMD3(0, 128, 800)) // col 0, row 1
        #expect(q0.positions[17 * 17 - 1] == SIMD3<Float>(2048, 2048, 800))
        // Quadrant 3 (NE) starts at global col/row 16.
        let q3 = patches[3].mesh
        #expect(q3.positions[0] == SIMD3<Float>(2048, 2048, 800))
    }

    @Test func normalizesVNML() throws {
        // Raw (127, 0, 0) -> (1, 0, 0) after /127 + normalize.
        let patches = try TerrainMeshBuilder.patches(
            land: land(normal: SIMD3<Int8>(127, 0, 0)), hiddenQuadrants: 0
        )
        let normal = patches[0].mesh.normals[0]
        #expect(abs(normal.x - 1) < 1e-5)
        #expect(abs(normal.y) < 1e-5)
        #expect(abs(normal.z) < 1e-5)
    }

    @Test func defaultsAbsentNormalsToUp() throws {
        let patches = try TerrainMeshBuilder.patches(land: land(normal: nil), hiddenQuadrants: 0)
        #expect(patches[0].mesh.normals[0] == SIMD3(0, 0, 1))
    }

    @Test func zeroNormalFallsBackToUp() throws {
        // A degenerate (0,0,0) VNML triple must not divide by zero.
        let patches = try TerrainMeshBuilder.patches(
            land: land(normal: SIMD3<Int8>(0, 0, 0)), hiddenQuadrants: 0
        )
        #expect(patches[0].mesh.normals[0] == SIMD3(0, 0, 1))
    }

    // MARK: - Hidden quadrants

    @Test func omitsHiddenQuadrants() throws {
        // XCLC bits 0x1 | 0x4 hide quadrants 0 and 2 -> only 1 and 3 emit.
        let patches = try TerrainMeshBuilder.patches(land: land(), hiddenQuadrants: 0x1 | 0x4)
        #expect(patches.count == 2)
        #expect(patches.map(\.quadrant) == [1, 3])
        #expect(patches.map(\.mesh.name) == ["terrain-quadrant-1", "terrain-quadrant-3"])
    }

    // MARK: - Splat inputs

    @Test func routesBaseTexturePerQuadrant() throws {
        // Fixture paints quadrant q's base with LTEX 0x1000+q; an unpainted
        // quadrant carries no base FormID.
        let patches = try TerrainMeshBuilder.patches(
            land: land(baseQuadrants: [0, 1, 3]), hiddenQuadrants: 0
        )
        #expect(patches.count == 4)
        #expect(patches[0].baseTexture == FormID(0x1000))
        #expect(patches[1].baseTexture == FormID(0x1001))
        #expect(patches[2].baseTexture == nil)
        #expect(patches[3].baseTexture == FormID(0x1003))
    }

    @Test func sortsLayersByLayerNumberPerQuadrant() throws {
        // Two layers for quadrant 2 arrive on disk in reverse layer order plus
        // one for quadrant 0 — the quadrant-2 patch keeps only its own, sorted
        // by layer number (splat blend order, UESP LAND).
        let patches = try TerrainMeshBuilder.patches(
            land: land(layers: [
                LayerSpec(quadrant: 2, layer: 1, formID: 0x21, samples: []),
                LayerSpec(quadrant: 2, layer: 0, formID: 0x20, samples: []),
                LayerSpec(quadrant: 0, layer: 0, formID: 0x10, samples: [])
            ]),
            hiddenQuadrants: 0
        )
        #expect(patches[2].layers.map(\.texture) == [FormID(0x20), FormID(0x21)])
        #expect(patches[0].layers.map(\.texture) == [FormID(0x10)])
        #expect(patches[1].layers.isEmpty)
    }

    @Test func bakesSparseVTXTDense() throws {
        // Positions index the 17x17 quadrant grid row-major (UESP LAND VTXT):
        // 0 = SW corner, 18 = (col 1, row 1), 288 = NE corner.
        let patches = try TerrainMeshBuilder.patches(
            land: land(layers: [LayerSpec(
                quadrant: 0, layer: 0, formID: 0x20,
                samples: [(0, 0.25), (18, 0.5), (288, 1.0)]
            )]),
            hiddenQuadrants: 0
        )
        let opacities = patches[0].layers[0].opacities
        #expect(opacities.count == 289)
        #expect(opacities[0] == 0.25)
        #expect(opacities[18] == 0.5)
        #expect(opacities[288] == 1.0)
        #expect(opacities[1] == 0)
    }

    @Test func denseBakeDropsOutOfRangeAndClampsOpacity() {
        let dense = TerrainMeshBuilder.denseOpacities([
            Land.AlphaSample(position: 289, opacity: 1), // past the 17x17 grid
            Land.AlphaSample(position: 5, opacity: 1.5), // clamps to 1
            Land.AlphaSample(position: 6, opacity: -0.5) // clamps to 0
        ])
        #expect(dense.count == 289)
        #expect(dense[5] == 1)
        #expect(dense[6] == 0)
        #expect(dense.reduce(0, +) == 1)
    }

    @Test func packsWeightsIntoTwoLanesPerVertex() {
        // Layer i lands in lane i: float4 index i/4, component i%4.
        var layer0 = [Float](repeating: 0, count: 3)
        var layer6 = [Float](repeating: 0, count: 3)
        layer0[1] = 0.75
        layer6[2] = 0.5
        let packed = TerrainMeshBuilder.packWeights(
            layers: [layer0, [], [], [], [], [], layer6], vertexCount: 3
        )
        #expect(packed.count == 6)
        #expect(packed[2].x == 0.75) // vertex 1, lane 0 -> weights0.x
        #expect(packed[5].z == 0.5) // vertex 2, lane 6 -> weights1.z
        #expect(packed[0] == .zero)
    }

    @Test func packWeightsIgnoresLayersOverTheCap() {
        // 9 layers, all weight 1: the ninth exceeds TerrainConstant.maxLayers
        // and must not wrap into another vertex's lanes.
        let layers = [[Float]](repeating: [1], count: 9)
        let packed = TerrainMeshBuilder.packWeights(layers: layers, vertexCount: 1)
        #expect(packed == [SIMD4<Float>(1, 1, 1, 1), SIMD4<Float>(1, 1, 1, 1)])
    }

    // MARK: - Fallback plane

    @Test func buildsFallbackPlaneAtDefaultLandHeight() {
        let patch = TerrainMeshBuilder.fallbackPatch(defaultLandHeight: -27000)
        #expect(patch.quadrant == nil)
        #expect(patch.baseTexture == nil)
        #expect(patch.layers.isEmpty)
        #expect(patch.mesh.positions.count == 33 * 33)
        #expect(patch.mesh.positions.allSatisfy { $0.z == -27000 })
        #expect(patch.mesh.normals.allSatisfy { $0 == SIMD3(0, 0, 1) })
        // Corners span the full 4096-unit cell footprint.
        #expect(patch.mesh.positions[0] == SIMD3(0, 0, -27000))
        #expect(patch.mesh.positions[33 * 33 - 1] == SIMD3(4096, 4096, -27000))
    }
}
