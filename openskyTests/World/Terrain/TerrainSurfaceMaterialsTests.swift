// Exterior ground's material comes from the landscape texture painted heaviest
// at each vertex (issue #358). Synthetic LAND records only.

import Foundation
@testable import opensky
import simd
import Testing

struct TerrainSurfaceMaterialsTests {
    /// LTEX FormIDs and the MATT each names, matching `Self.materialTypes`.
    private static let snowTexture = FormID(0x300)
    private static let stoneTexture = FormID(0x301)
    private static let unmappedTexture = FormID(0x302)
    private static let snow = FormID(0x101)
    private static let stone = FormID(0x102)

    private static let materialTypes = MaterialTypeIndex(
        materials: [
            MaterialType(formID: snow, editorID: "MaterialSnow", materialName: "Snow"),
            MaterialType(formID: stone, editorID: "MaterialStone", materialName: "Stone")
        ],
        landTextureMaterials: [
            snowTexture: snow,
            stoneTexture: stone,
            unmappedTexture: nil
        ]
    )

    @Test func anUnpaintedQuadrantResolvesToTheBaseTexture() throws {
        let land = try Self.land(baseTextures: [(Self.stoneTexture, 0)])
        let materials = try #require(
            TerrainSurfaceMaterials.build(land: land, materialTypes: Self.materialTypes)
        )

        #expect(materials.material(column: 0, row: 0) == Self.stone)
        #expect(materials.material(column: 8, row: 8) == Self.stone)
        // Quadrant 0 is the south-west one, so the far corner is unpainted.
        #expect(materials.material(column: 32, row: 32) == nil)
    }

    /// A layer at full opacity replaces the base under it and leaves the rest
    /// of the quadrant alone. This is the case the issue names: snow painted
    /// over rock has to sound like snow only where it is painted.
    @Test func aFullyOpaqueLayerWinsOnlyWhereItIsPainted() throws {
        let land = try Self.land(
            baseTextures: [(Self.stoneTexture, 0)],
            layers: [Layer(
                texture: Self.snowTexture,
                quadrant: 0,
                layer: 1,
                alphas: [(position: 0, opacity: 1)]
            )]
        )
        let materials = try #require(
            TerrainSurfaceMaterials.build(land: land, materialTypes: Self.materialTypes)
        )

        #expect(materials.material(column: 0, row: 0) == Self.snow)
        #expect(materials.material(column: 1, row: 0) == Self.stone)
    }

    @Test func theHeavierOfTwoPartialLayersWins() throws {
        let land = try Self.land(
            baseTextures: [(Self.stoneTexture, 0)],
            layers: [Layer(
                texture: Self.snowTexture,
                quadrant: 0,
                layer: 1,
                alphas: [(position: 0, opacity: 0.7)]
            )]
        )
        let materials = try #require(
            TerrainSurfaceMaterials.build(land: land, materialTypes: Self.materialTypes)
        )

        // 0.7 snow over 0.3 of what the base had left.
        #expect(materials.material(column: 0, row: 0) == Self.snow)
    }

    @Test func aQuadrantPaintsItsOwnCornerOfTheGrid() throws {
        let land = try Self.land(baseTextures: [
            (Self.stoneTexture, 0),
            (Self.snowTexture, 3)
        ])
        let materials = try #require(
            TerrainSurfaceMaterials.build(land: land, materialTypes: Self.materialTypes)
        )

        #expect(materials.material(column: 0, row: 0) == Self.stone)
        #expect(materials.material(column: 32, row: 32) == Self.snow)
    }

    @Test func aTextureNamingNoMaterialResolvesToNothing() throws {
        let land = try Self.land(baseTextures: [(Self.unmappedTexture, 0)])

        #expect(
            TerrainSurfaceMaterials.build(land: land, materialTypes: Self.materialTypes) == nil
        )
    }

    @Test func aLandWithNoTexturesResolvesToNothing() throws {
        let land = try Self.land()

        #expect(
            TerrainSurfaceMaterials.build(land: land, materialTypes: Self.materialTypes) == nil
        )
    }

    /// The height field carries the grid, so a ground sample names the material
    /// at the vertex nearest the point rather than blending two of them.
    @Test func theGroundSampleReportsTheMaterialAtTheNearestVertex() throws {
        let land = try Self.land(
            baseTextures: [(Self.stoneTexture, 0)],
            layers: [Layer(
                texture: Self.snowTexture,
                quadrant: 0,
                layer: 1,
                alphas: [(position: 0, opacity: 1)]
            )]
        )
        let field = try #require(TerrainHeightField(
            coordinate: CellCoordinate(x: 0, y: 0),
            heights: [Float](repeating: 0, count: Land.vertexCount),
            surfaceMaterials: TerrainSurfaceMaterials.build(
                land: land,
                materialTypes: Self.materialTypes
            )
        ))

        let quad = TerrainMeshBuilder.quadSize
        #expect(field.sample(at: SIMD2(1, 1))?.material == Self.snow)
        #expect(field.sample(at: SIMD2(quad * 0.9, 1))?.material == Self.stone)
    }

    @Test func aHeightFieldWithNoMaterialsReportsNone() throws {
        let field = try #require(TerrainHeightField(
            coordinate: CellCoordinate(x: 0, y: 0),
            heights: [Float](repeating: 0, count: Land.vertexCount)
        ))

        #expect(field.sample(at: SIMD2(1, 1))?.material == nil)
    }

    // MARK: - Fixtures

    /// One ATXT layer plus the VTXT alphas that follow it.
    private struct Layer {
        let texture: FormID
        let quadrant: UInt8
        let layer: Int16
        let alphas: [(position: UInt16, opacity: Float)]
    }

    private static func land(
        baseTextures: [(texture: FormID, quadrant: UInt8)] = [],
        layers: [Layer] = []
    ) throws -> Land {
        var fields = Data()
        for base in baseTextures {
            fields += ESMFixture.field(
                "BTXT",
                textureHeader(texture: base.texture, quadrant: base.quadrant, layer: 0)
            )
        }
        for layer in layers {
            fields += ESMFixture.field(
                "ATXT",
                textureHeader(
                    texture: layer.texture,
                    quadrant: layer.quadrant,
                    layer: layer.layer
                )
            )
            fields += ESMFixture.field("VTXT", vtxt(layer.alphas))
        }
        let bytes = ESMFixture.record("LAND", data: fields)
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return try Land(record: record)
    }

    private static func textureHeader(
        texture: FormID,
        quadrant: UInt8,
        layer: Int16
    ) -> Data {
        var data = Data()
        data.appendUInt32(texture.rawValue)
        data.append(quadrant)
        data.append(0) // unused
        data.appendUInt16(UInt16(bitPattern: layer))
        return data
    }

    private static func vtxt(_ samples: [(position: UInt16, opacity: Float)]) -> Data {
        var data = Data()
        for sample in samples {
            data.appendUInt16(sample.position)
            data.appendUInt16(0) // unused
            data.appendFloat32(sample.opacity)
        }
        return data
    }
}
