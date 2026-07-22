// Pure procedural grass placement tests over synthetic LAND/LTEX/GRAS
// records. Covers deterministic seeding, splat coverage, terrain limits, and
// GRAS variance controls without game assets.

import Foundation
@testable import opensky
import simd
import Testing

struct GrassPlacementTests {
    @Test func fullCoverageProducesDeterministicVariedPlacements() throws {
        let grassID: UInt32 = 0x200
        let textureID: UInt32 = 0x100
        let land = try makeLand(baseTexture: textureID, vertexColor: SIMD3(128, 96, 64))
        let grass = try makeGrass(
            formID: grassID,
            positionRange: 512,
            heightRange: 0.5,
            colorRange: 0.5,
            flags: 0x02
        )
        let heights = try #require(land.heightField?.heights)
        let field = try #require(TerrainHeightField(
            coordinate: CellCoordinate(x: 6, y: -2),
            heights: heights
        ))
        let textures = try [textureID: makeLandTexture(
            formID: textureID,
            grasses: [grassID]
        )]
        let grasses = [grassID: grass]

        let first = GrassPlacementBuilder.placements(
            land: land,
            heightField: field,
            landTextures: textures,
            grasses: grasses
        )
        let second = GrassPlacementBuilder.placements(
            land: land,
            heightField: field,
            landTextures: textures,
            grasses: grasses
        )

        #expect(first == second)
        #expect(first.count == 64)
        #expect(first.allSatisfy { $0.position.z == 40 })
        #expect(first.allSatisfy { $0.normal == SIMD3(0, 0, 1) })
        #expect(first.allSatisfy { $0.scale.x == $0.scale.z && $0.scale.y == $0.scale.z })
        #expect(first.allSatisfy { (0.5 ... 1.5).contains($0.scale.z) })
        #expect(first.contains { $0.scale.z != 1 })
        #expect(first.allSatisfy { (0 ... 128.0 / 255).contains($0.color.x) })
        #expect(first.allSatisfy { (0 ... 96.0 / 255).contains($0.color.y) })
        #expect(first.contains { $0.color.x < 128.0 / 255 })
        #expect(first.contains { placement in
            let localX = placement.position.x - Float(field.coordinate.x) * 4096
            return abs(localX.truncatingRemainder(dividingBy: 512) - 256) > 1
        })
    }

    @Test func neighboringCellUsesDifferentSeed() throws {
        let fixture = try fullCoverageFixture()
        let heights = try #require(fixture.land.heightField?.heights)
        let firstField = try #require(TerrainHeightField(
            coordinate: CellCoordinate(x: 0, y: 0),
            heights: heights
        ))
        let nextField = try #require(TerrainHeightField(
            coordinate: CellCoordinate(x: 1, y: 0),
            heights: heights
        ))
        let first = GrassPlacementBuilder.placements(
            land: fixture.land,
            heightField: firstField,
            landTextures: fixture.textures,
            grasses: fixture.grasses
        )
        let next = GrassPlacementBuilder.placements(
            land: fixture.land,
            heightField: nextField,
            landTextures: fixture.textures,
            grasses: fixture.grasses
        )
        let firstLocal = first.map { SIMD2($0.position.x, $0.position.y) }
        let nextLocal = next.map { SIMD2($0.position.x - 4096, $0.position.y) }
        #expect(firstLocal != nextLocal)
    }

    @Test func additionalLANDLayerDrivesCoverage() throws {
        let baseID: UInt32 = 0x100
        let paintedID: UInt32 = 0x101
        let grassID: UInt32 = 0x200
        let land = try makeLand(
            baseTexture: baseID,
            paintedTexture: paintedID,
            paintedQuadrant: 0,
            paintedOpacity: 1
        )
        let heights = try #require(land.heightField?.heights)
        let field = try #require(TerrainHeightField(
            coordinate: CellCoordinate(x: 0, y: 0),
            heights: heights
        ))
        let placements = try GrassPlacementBuilder.placements(
            land: land,
            heightField: field,
            landTextures: [
                baseID: makeLandTexture(formID: baseID, grasses: []),
                paintedID: makeLandTexture(formID: paintedID, grasses: [grassID])
            ],
            grasses: [grassID: makeGrass(formID: grassID, positionRange: 512)]
        )
        #expect(!placements.isEmpty)
        #expect(placements.count < 64)
        #expect(placements.allSatisfy { $0.position.x < 2048 && $0.position.y < 2048 })
    }

    @Test func densitySlopeWaterAndHiddenQuadrantsFilter() throws {
        let fixture = try fullCoverageFixture()
        let heights = try #require(fixture.land.heightField?.heights)
        let flat = try #require(TerrainHeightField(
            coordinate: CellCoordinate(x: 0, y: 0),
            heights: heights
        ))
        let zeroDensity = try makeGrass(formID: 0x200, density: 0, positionRange: 512)
        #expect(GrassPlacementBuilder.placements(
            land: fixture.land,
            heightField: flat,
            landTextures: fixture.textures,
            grasses: [0x200: zeroDensity]
        ).isEmpty)

        let steepOnly = try makeGrass(
            formID: 0x200,
            minimumSlope: 30,
            maximumSlope: 90,
            positionRange: 512
        )
        #expect(GrassPlacementBuilder.placements(
            land: fixture.land,
            heightField: flat,
            landTextures: fixture.textures,
            grasses: [0x200: steepOnly]
        ).isEmpty)

        let waterLimited = try makeGrass(
            formID: 0x200,
            unitsFromWater: 100,
            waterRule: 0,
            positionRange: 512
        )
        #expect(GrassPlacementBuilder.placements(
            land: fixture.land,
            heightField: flat,
            landTextures: fixture.textures,
            grasses: [0x200: waterLimited],
            waterHeight: 0
        ).isEmpty)

        let hidden = try #require(TerrainHeightField(
            coordinate: CellCoordinate(x: 0, y: 0),
            heights: heights,
            hiddenQuadrants: 0x01
        ))
        let visible = GrassPlacementBuilder.placements(
            land: fixture.land,
            heightField: hidden,
            landTextures: fixture.textures,
            grasses: fixture.grasses
        )
        #expect(!visible.isEmpty && visible.count < 64)
        #expect(visible.allSatisfy { !($0.position.x < 2048 && $0.position.y < 2048) })
    }
}

extension GrassPlacementTests {
    private struct Fixture {
        let land: Land
        let textures: [UInt32: LandTexture]
        let grasses: [UInt32: Grass]
    }

    private func fullCoverageFixture() throws -> Fixture {
        let textureID: UInt32 = 0x100
        let grassID: UInt32 = 0x200
        return try Fixture(
            land: makeLand(baseTexture: textureID),
            textures: [textureID: makeLandTexture(
                formID: textureID,
                grasses: [grassID]
            )],
            grasses: [grassID: makeGrass(formID: grassID, positionRange: 512)]
        )
    }

    private func makeLand(
        baseTexture: UInt32,
        paintedTexture: UInt32? = nil,
        paintedQuadrant: UInt8 = 0,
        paintedOpacity: Float = 0,
        vertexColor: SIMD3<UInt8>? = nil
    ) throws -> Land {
        var vhgt = Data()
        vhgt.appendFloat32(5)
        vhgt.append(contentsOf: [UInt8](repeating: 0, count: Land.vertexCount))
        vhgt.append(contentsOf: [0, 0, 0])
        var fields = ESMFixture.field("VHGT", vhgt)
        if let vertexColor {
            var colors = Data()
            for _ in 0 ..< Land.vertexCount {
                colors.append(vertexColor.x)
                colors.append(vertexColor.y)
                colors.append(vertexColor.z)
            }
            fields += ESMFixture.field("VCLR", colors)
        }
        for quadrant in UInt8(0) ... 3 {
            fields += ESMFixture.field(
                "BTXT",
                textureHeader(texture: baseTexture, quadrant: quadrant, layer: 0)
            )
        }
        if let paintedTexture {
            fields += ESMFixture.field(
                "ATXT",
                textureHeader(
                    texture: paintedTexture,
                    quadrant: paintedQuadrant,
                    layer: 1
                )
            )
            var opacity = Data()
            for position in UInt16(0) ..< UInt16(289) {
                opacity.appendUInt16(position)
                opacity.appendUInt16(0)
                opacity.appendFloat32(paintedOpacity)
            }
            fields += ESMFixture.field("VTXT", opacity)
        }
        return try Land(record: record(ESMFixture.record("LAND", formID: 0x300, data: fields)))
    }

    private func makeLandTexture(
        formID: UInt32,
        grasses: [UInt32]
    ) throws -> LandTexture {
        var fields = Data()
        for grass in grasses {
            var gnam = Data()
            gnam.appendUInt32(grass)
            fields += ESMFixture.field("GNAM", gnam)
        }
        return try LandTexture(record: record(
            ESMFixture.record("LTEX", formID: formID, data: fields)
        ))
    }

    private func makeGrass(
        formID: UInt32,
        density: UInt8 = 100,
        minimumSlope: UInt8 = 0,
        maximumSlope: UInt8 = 90,
        unitsFromWater: UInt16 = 0,
        waterRule: UInt32 = 0,
        positionRange: Float,
        heightRange: Float = 0,
        colorRange: Float = 0,
        flags: UInt8 = 0
    ) throws -> Grass {
        var data = Data()
        data.append(density)
        data.append(minimumSlope)
        data.append(maximumSlope)
        data.append(0)
        data.appendUInt16(unitsFromWater)
        data.appendUInt16(0)
        data.appendUInt32(waterRule)
        data.appendFloat32(positionRange)
        data.appendFloat32(heightRange)
        data.appendFloat32(colorRange)
        data.appendFloat32(1)
        data.append(flags)
        data.append(contentsOf: [0, 0, 0])
        let fields = ESMFixture.field("MODL", ESMFixture.zstring("grass.nif"))
            + ESMFixture.field("DATA", data)
        return try Grass(record: record(
            ESMFixture.record("GRAS", formID: formID, data: fields)
        ))
    }

    private func textureHeader(texture: UInt32, quadrant: UInt8, layer: Int16) -> Data {
        var data = Data()
        data.appendUInt32(texture)
        data.append(quadrant)
        data.append(0)
        data.appendUInt16(UInt16(bitPattern: layer))
        return data
    }

    private func record(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }
}
