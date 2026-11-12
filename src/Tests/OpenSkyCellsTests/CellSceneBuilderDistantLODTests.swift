// The distant ring of a worldspace: its LOD settings file, the distant water past the
// loaded cells, and a child world that draws its parent's LOD. No LOD mesh exists, so
// every block counts as missing. Synthetic plugin only.

import Foundation
@testable import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyFormatsTesting
import OpenSkyRendering
import OpenSkyTagsTesting
import OpenSkyTerrain
import OpenSkyWorldTesting
import simd
import Testing

@Suite(.tags(.gpu), .unlessPlanSkips(.gpu))
struct CellSceneBuilderDistantLODTests: CellSceneBuilderFixture {
    let dataURL: URL
    private let center = CellCoordinate(x: 6, y: -2)

    init() throws {
        dataURL = try Self.makeDataDirectory()
    }

    /// A 256 x 256 cell area from (-96, -96), with LOD levels 4 to 32.
    private func writeSettings(worldspace: String) throws {
        var data = Data()
        data.appendUInt16(UInt16(bitPattern: -96))
        data.appendUInt16(UInt16(bitPattern: -96))
        data.appendUInt32(256)
        data.appendUInt32(4)
        data.appendUInt32(32)
        try writeLooseFile("lodsettings/\(worldspace).lod", data)
    }

    private func makeBuilder(_ pluginData: Data) throws -> CellSceneBuilder {
        let device = try #require(Self.device)
        return try makeBuilder(pluginData: pluginData, device: device)
    }

    /// The cells each water plane spans, from the plane's scale.
    private func cellArea(_ water: [WaterDrawItem]) -> Float {
        water.reduce(0) { $0 + $1.modelMatrix.columns.0.x * $1.modelMatrix.columns.1.y }
    }

    @Test(.enabled(if: Self.hasDevice)) func aWorldWithoutASettingsFileHasNoRing() throws {
        let terrain = try makeBuilder(plugin()).terrainBuilder
        #expect(throws: (any Error).self) {
            try terrain.buildDistantLOD(
                worldspaceEditorID: "Tamriel",
                center: center,
                hiddenCells: []
            )
        }
    }

    @Test(.enabled(if: Self.hasDevice)) func theRingDrawsWaterOverTheWholeArea() throws {
        try writeSettings(worldspace: "tamriel")
        let terrain = try makeBuilder(plugin(worldDefaultWaterHeight: -500)).terrainBuilder
        let ring = try #require(try terrain.buildDistantLOD(
            worldspaceEditorID: "Tamriel", center: center, hiddenCells: []
        ))
        #expect(ring.blockCount == 0)
        #expect(ring.missingBlockCount > 0)
        let water = ring.renderScene.water
        #expect(!water.isEmpty)
        #expect(water.allSatisfy { $0.modelMatrix.columns.3.z == -500 })
        #expect(cellArea(water) == 256 * 256)
        #expect(ring.largeReferenceCount == 0)
        #expect(ring.fullLODReferenceCount == 0)
    }

    @Test(.enabled(if: Self.hasDevice)) func aLoadedCellLeavesAGapInTheWater() throws {
        try writeSettings(worldspace: "tamriel")
        let terrain = try makeBuilder(plugin(worldDefaultWaterHeight: -500)).terrainBuilder
        let ring = try #require(try terrain.buildDistantLOD(
            worldspaceEditorID: "Tamriel", center: center, hiddenCells: [center]
        ))
        #expect(cellArea(ring.renderScene.water) == 256 * 256 - 1)
    }

    @Test(.enabled(if: Self.hasDevice)) func noLODWaterAndNoWaterHeightDrawNoWater() throws {
        try writeSettings(worldspace: "tamriel")
        let flagged = try makeBuilder(plugin(worldDefaultWaterHeight: -500, worldFlags: 0x08))
        let dry = try makeBuilder(plugin())
        for builder in [flagged, dry] {
            let ring = try #require(try builder.terrainBuilder.buildDistantLOD(
                worldspaceEditorID: "Tamriel", center: center, hiddenCells: []
            ))
            #expect(ring.renderScene.water.isEmpty)
        }
    }

    @Test(.enabled(if: Self.hasDevice)) func aChildWorldDrawsItsParentsLOD() throws {
        try writeSettings(worldspace: "tamriel")
        let parent = worldRecord(formID: 0x3C, editorID: "Tamriel")
        let terrain = try makeBuilder(plugin(
            worldspaceEditorID: "WhiterunWorld",
            worldDefaultWaterHeight: -10,
            parentWorld: 0x3C,
            parentFlags: 0x0002,
            extraWorldRecords: parent
        )).terrainBuilder
        #expect(terrain.lodWorldspace(of: "WhiterunWorld") == "Tamriel")
        #expect(terrain.lodWorldspace(of: "Nowhere") == "Nowhere")
        let ring = try #require(try terrain.buildDistantLOD(
            worldspaceEditorID: "WhiterunWorld", center: center, hiddenCells: []
        ))
        #expect(ring.missingBlockCount > 0)
        #expect(ring.renderScene.water.allSatisfy { $0.modelMatrix.columns.3.z == -10 })
        #expect(!ring.renderScene.water.isEmpty)
    }
}
