// TerrainMeshBuilder tests over synthetic in-code LAND values (built via the
// same helpers as TerrainRecordDecoderTests) — never extracted game files
// (AGENTS.md "Legal & IP boundary"). Verify grid geometry (128-unit quads,
// height passthrough), VNML normalization, per-quadrant topology + shared
// edges, hidden-quadrant omission, and the LAND-less fallback plane.

import Foundation
@testable import opensky
import simd
import Testing

struct TerrainMeshBuilderTests {
    // MARK: - Land fixtures

    /// A LAND with a flat height field at `height` game units, optional VNML
    /// triple applied to every vertex, and a BTXT base per listed quadrant.
    private func land(
        height: Float = 0,
        normal: SIMD3<Int8>? = nil,
        baseQuadrants: [UInt8] = [0, 1, 2, 3]
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
        let bytes = ESMFixture.record("LAND", data: fields)
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a LAND record")
        }
        return try Land(record: record)
    }

    // MARK: - Geometry

    @Test func buildsFourQuadrantsWithSharedEdgeVertices() throws {
        let model = try TerrainMeshBuilder.model(
            land: land(), hiddenQuadrants: 0, materialForQuadrant: { _ in .fallback }
        )
        #expect(model.meshes.count == 4)
        #expect(model.materials.count == 4)
        for mesh in model.meshes {
            // 17x17 vertices, 16x16 quads * 2 triangles * 3 indices.
            #expect(mesh.positions.count == 17 * 17)
            #expect(mesh.indices.count == 16 * 16 * 6)
            #expect(mesh.indices.allSatisfy { $0 < UInt16(mesh.positions.count) })
        }
        // Quadrant 0 (SW) and quadrant 1 (SE) share the center column (col 16):
        // q0's east edge equals q1's west edge in world position.
        let q0 = model.meshes[0]
        let q1 = model.meshes[1]
        for row in 0 ..< 17 {
            let q0East = q0.positions[row * 17 + 16] // col 16 within q0
            let q1West = q1.positions[row * 17 + 0] // col 16 globally, local 0
            #expect(q0East == q1West)
        }
    }

    @Test func mapsGridToWorldWithQuadSizeAndHeight() throws {
        let model = try TerrainMeshBuilder.model(
            land: land(height: 800), hiddenQuadrants: 0,
            materialForQuadrant: { _ in .fallback }
        )
        let q0 = model.meshes[0]
        // Local (col, row) -> world (col*128, row*128, height). Flat at 800.
        #expect(q0.positions[0] == SIMD3(0, 0, 800)) // col 0, row 0
        #expect(q0.positions[1] == SIMD3(128, 0, 800)) // col 1, row 0
        #expect(q0.positions[17] == SIMD3(0, 128, 800)) // col 0, row 1
        #expect(q0.positions[17 * 17 - 1] == SIMD3<Float>(2048, 2048, 800))
        // Quadrant 3 (NE) starts at global col/row 16.
        let q3 = model.meshes[3]
        #expect(q3.positions[0] == SIMD3<Float>(2048, 2048, 800))
    }

    @Test func normalizesVNML() throws {
        // Raw (127, 0, 0) -> (1, 0, 0) after /127 + normalize.
        let model = try TerrainMeshBuilder.model(
            land: land(normal: SIMD3<Int8>(127, 0, 0)), hiddenQuadrants: 0,
            materialForQuadrant: { _ in .fallback }
        )
        let normal = model.meshes[0].normals[0]
        #expect(abs(normal.x - 1) < 1e-5)
        #expect(abs(normal.y) < 1e-5)
        #expect(abs(normal.z) < 1e-5)
    }

    @Test func defaultsAbsentNormalsToUp() throws {
        let model = try TerrainMeshBuilder.model(
            land: land(normal: nil), hiddenQuadrants: 0,
            materialForQuadrant: { _ in .fallback }
        )
        #expect(model.meshes[0].normals[0] == SIMD3(0, 0, 1))
    }

    @Test func zeroNormalFallsBackToUp() throws {
        // A degenerate (0,0,0) VNML triple must not divide by zero.
        let model = try TerrainMeshBuilder.model(
            land: land(normal: SIMD3<Int8>(0, 0, 0)), hiddenQuadrants: 0,
            materialForQuadrant: { _ in .fallback }
        )
        #expect(model.meshes[0].normals[0] == SIMD3(0, 0, 1))
    }

    // MARK: - Hidden quadrants

    @Test func omitsHiddenQuadrants() throws {
        // XCLC bits 0x1 | 0x4 hide quadrants 0 and 2 -> only 1 and 3 emit.
        let model = try TerrainMeshBuilder.model(
            land: land(), hiddenQuadrants: 0x1 | 0x4,
            materialForQuadrant: { _ in .fallback }
        )
        #expect(model.meshes.count == 2)
        #expect(model.meshes.map(\.name) == ["terrain-quadrant-1", "terrain-quadrant-3"])
    }

    @Test func passesResolvedMaterialPerQuadrant() throws {
        // materialForQuadrant is consulted per quadrant; distinct diffuse keys
        // land in distinct material slots referenced by the meshes.
        let model = try TerrainMeshBuilder.model(
            land: land(), hiddenQuadrants: 0,
            materialForQuadrant: { quadrant in
                Material(
                    diffuseTexture: "textures/q\(quadrant).dds", normalTexture: nil,
                    uvOffset: .zero, uvScale: SIMD2(1, 1), alpha: 1, glossiness: 80,
                    specularColor: SIMD3(1, 1, 1), specularStrength: 1,
                    doubleSided: false, alphaBlend: false, alphaTestThreshold: nil
                )
            }
        )
        for (index, mesh) in model.meshes.enumerated() {
            #expect(model.materials[mesh.materialSlot].diffuseTexture == "textures/q\(index).dds")
        }
    }

    // MARK: - Fallback plane

    @Test func buildsFallbackPlaneAtDefaultLandHeight() {
        let model = TerrainMeshBuilder.fallbackModel(defaultLandHeight: -27000)
        #expect(model.meshes.count == 1)
        #expect(model.materials == [.fallback])
        let mesh = model.meshes[0]
        #expect(mesh.positions.count == 33 * 33)
        #expect(mesh.positions.allSatisfy { $0.z == -27000 })
        #expect(mesh.normals.allSatisfy { $0 == SIMD3(0, 0, 1) })
        // Corners span the full 4096-unit cell footprint.
        #expect(mesh.positions[0] == SIMD3(0, 0, -27000))
        #expect(mesh.positions[33 * 33 - 1] == SIMD3(4096, 4096, -27000))
    }
}
